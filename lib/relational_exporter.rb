require 'byebug'
require 'csv'
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

    def export(output_config, &block)
      ActiveRecord::Base.logger = @logger
      Celluloid.logger = @logger

      output_config = Hashie::Mash.new output_config

      main_klass = output_config.output.model.to_s.classify.constantize

      main_klass.set_scope_from_hash output_config.output.scope.as_json

      csv_builder = RelationalExporter::CsvBuilder.new output_config.file_path
      Celluloid::Actor[:csv_builder] = csv_builder
      result = csv_builder.future.start
      pool = RelationalExporter::RecordWorker.pool size: 8
      get_headers = true

      record_sequence = -1
      main_klass.find_all_by_scope(output_config.output.scope.as_json).find_in_batches(batch_size: 100) do |records|
        records.each do |record|
          record_sequence += 1
          pool.async.get_csv_row(record_sequence, record, output_config.output.associations, get_headers)
          get_headers = false if get_headers
        end
      end

      csv_builder.end_index = record_sequence

      @logger.info "CSV export complete" if result.value === true

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
