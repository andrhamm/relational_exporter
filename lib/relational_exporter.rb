require 'csv'
require 'benchmark'
require 'hashie'
require 'relational_exporter/version'
require 'relational_exporter/active_record_extension'
require 'relational_exporter/csv_builder'
require 'relational_exporter/record_worker'
require 'celluloid'

module RelationalExporter
  class Runner
    attr_accessor :schema, :logger

    def initialize(options={})
      @logger = options[:logger] ? options[:logger] : Logger.new(STDERR)

      @connection_config = options[:connection_config]
      begin
        ActiveRecord::Base.establish_connection @connection_config
        ActiveRecord::Base.connection.active?
      rescue Exception => e
        raise "Database connection failed: #{e.message}"
      end

      @schema = Hashie::Mash.new(options[:schema] || YAML.load_file(options[:schema_file]))

      load_models
    end

    def export(options, &block)
      ActiveRecord::Base.logger = @logger
      Celluloid.logger = @logger

      options = Hashie::Mash.new options

      main_klass = options.output.model.to_s.classify.constantize

      main_klass.set_scope_from_hash options.output.scope.as_json

      total_records = main_klass.find_all_by_scope(options.output.scope.as_json).count
      remaining_records = total_records

      csv_builder = RelationalExporter::CsvBuilder.new options.file_path
      Celluloid::Actor[:csv_builder] = csv_builder
      result = csv_builder.future.start
      pool_size = options.workers || 10
      pool = RelationalExporter::RecordWorker.pool(size: pool_size)
      get_headers = true

      record_sequence = -1
      batch_count = 0

      batch_options = Hashie::Mash.new({batch_size: 100}.merge(options.batch_options || {}))
      limit = options.limit.nil? ? nil : options.limit.to_i
      max_records = limit.nil? ? total_records : [limit, total_records].min

      @logger.info "CSV export will process #{max_records} of #{total_records} total records."

      all_bm = Benchmark.measure do
        catch(:hit_limit) do
          main_klass.find_all_by_scope(options.output.scope.as_json).find_in_batches(batch_options.to_h.symbolize_keys) do |records|
            batch_count+=1
            batch_bm = Benchmark.measure do
              records.each do |record|
                record_sequence += 1
                remaining_records -= 1

                args = [record_sequence, record, options.output.associations, get_headers]
                if get_headers
                  pool.get_csv_row(*args)
                  get_headers = false
                else
                  pool.async.get_csv_row(*args)
                end

                throw :hit_limit if !limit.nil? && (record_sequence == max_records)
              end
            end

            @logger.debug "Batch of #{records.size} queued. #{remaining_records} remaining. Benchmark: #{batch_bm}"
          end
        end

        csv_builder.end_index = record_sequence

        @logger.info "CSV export complete <#{options.file_path}>" if result.value === true
      end

      @logger.debug "#{batch_count} batches processed. Benchmark: #{all_bm}"

      pool.terminate
      csv_builder.terminate
    end

    private

    def symbolize_options(options)
      options = options.as_json
      if options.is_a? Hash
        options.deep_symbolize_keys!
      elsif options.is_a? Array
        options.map { |val| symbolize_options val }
      end
    end

    def load_models
      @schema.each do |model, options|
        klass = Object.const_set model.to_s.classify, Class.new(ActiveRecord::Base)
        # klass.extend ActiveRecordExtension
        options.each do |method, calls|
          method = "#{method}=".to_sym if klass.respond_to?("#{method}=")
          if calls.respond_to? :each_pair
            calls.each do |association, association_options|
              association_options = symbolize_options association_options
              klass.send method, association.to_sym, *association_options
            end
          else
            klass.send method, *calls
          end
        end
      end
    end
  end
end
