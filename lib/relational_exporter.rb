require 'byebug'
require 'csv'
require 'hashie'
require 'relational_exporter/version'
require 'relational_exporter/active_record_extension'

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

      output_config = Hashie::Mash.new output_config

      main_klass = output_config.output.model.to_s.classify.constantize

      main_klass.set_scope_from_hash output_config.output.scope.as_json

      header_row = []
      max_associations = {}

      csv_options = {headers: true}
      if output_config.file_path.blank?
        csv_method = :instance
        csv_args = [STDOUT, csv_options]
      else
        csv_method = :open
        csv_args = [output_config.file_path, 'wb', csv_options]
      end

      ::CSV.send(csv_method, *csv_args) do |csv|
        main_klass.find_all_by_scope(output_config.output.scope.as_json).find_in_batches do |batch|
          batch.each do |single|
            if block_given?
              yield single

              return unless single
            end

            row = []

            # Add main record headers
            if !main_klass.active_model_serializer.blank?
              main_attributes = main_klass.active_model_serializer.new(single).as_json(root: false) rescue nil
            elsif defined?(BaseSerializer)
              main_attributes = BaseSerializer.new(single).as_json(root: false) rescue nil
            end

            main_attributes = single.attributes if main_attributes.nil?

            main_attributes.each do |field, value|
              header_row << [main_klass.to_s.underscore, field].join('_').classify if csv.header_row?
              row << value
            end

            output_config.output.associations.each do |association_accessor, association_options|
              association_accessor = association_accessor.to_s.to_sym
              association_klass = association_accessor.to_s.classify.constantize
              scope = symbolize_options association_options.scope

              associated = single.send association_accessor
              # TODO - this might suck for single associations (has_one) because they don't return an ar::associations::collectionproxy
              associated = associated.find_all_by_scope(scope) unless scope.blank? || !associated.respond_to?(:find_all_by_scope)

              if associated.is_a? Hash
                associated = [ associated ]
              elsif associated.blank?
                associated = []
              end

              foreign_key = main_klass.reflections[association_accessor].foreign_key rescue nil

              fields = association_klass.first.attributes.keys

              fields.reject! {|v| v == foreign_key } if foreign_key

              if csv.header_row?
                case main_klass.reflections[association_accessor].macro
                when :has_many
                  max_associated = association_klass.find_all_by_scope(scope)
                                                    .joins(main_klass.table_name.to_sym)
                                                    .order('count_all desc')
                                                    .group(foreign_key)
                                                    .limit(1).count.flatten[1]
                when :has_one
                  max_associated = 1
                end

                max_associations[association_accessor] = max_associated

                max_associated.times do |i|
                  fields.each do |field|
                    header_row << [association_klass.to_s.underscore, i+1, field].join('_').classify
                  end
                end
              end

              get_row_arr(associated, fields, max_associations[association_accessor]) {|field| row << field}
            end

            csv << header_row if csv.header_row?
            if row.count != header_row.count
              puts "OH SHIT, this row is not right!"
            end
            csv << row
          end
        end
      end
    end

    private

    def get_row_arr(records, fields, max_count=1, &block)
      max_count.times do |i|
        fields.each do |field|
          val = records[i][field] rescue nil
          yield val
        end
      end
    end

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
