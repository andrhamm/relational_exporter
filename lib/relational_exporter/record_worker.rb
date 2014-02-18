require 'celluloid'

module RelationalExporter
  class RecordWorker
    include Celluloid
    include Celluloid::Logger

    trap_exit :actor_died
    def actor_died(actor, reason)
      puts "Oh no! #{actor.inspect} has died because of a #{reason.class}" unless reason.nil?
    end

    @@MAX_ASSOCIATED = {}

    def get_csv_row(record_sequence, record, associations, with_headers=false)
      @record = record
      @associations = associations

      get_rows with_headers

      Celluloid::Actor[:csv_builder].queue[record_sequence] = [@header_row, @value_row]
    end

    def get_rows(get_headers=false)
      @header_row = []
      @value_row = []
      main_klass = @record.class

      RecordWorker.serialized_attributes_for_object_or_class(@record).each do |field, value|
        @header_row << RecordWorker.csv_header_prefix_for_key(main_klass, field) if get_headers
        @value_row << value
      end

      @associations.each do |association_accessor, association_options|
        association_accessor = association_accessor.to_s.to_sym
        association_klass = association_accessor.to_s.classify.constantize
        scope = RecordWorker.symbolize_options association_options.scope

        associated = @record.send association_accessor
        # TODO - this might suck for single associations (has_one) because they don't return an ar::associations::collectionproxy
        associated = associated.find_all_by_scope(scope) unless scope.blank? || !associated.respond_to?(:find_all_by_scope)

        if associated.is_a? Hash
          associated = [ associated ]
        elsif associated.blank?
          associated = []
        end

        foreign_key = main_klass.reflections[association_accessor].foreign_key rescue nil

        fields = RecordWorker.serialized_attributes_for_object_or_class(association_klass).keys

        fields.reject! {|v| v == foreign_key } if foreign_key

        if get_headers
          @@MAX_ASSOCIATED[association_accessor] ||= begin
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

            max_associated = 0 if max_associated.nil?
            max_associated
          end

          @@MAX_ASSOCIATED[association_accessor].times do |i|
            fields.each do |field|
              @header_row << RecordWorker.csv_header_prefix_for_key(association_klass, field, i+1)
            end
          end
        end

        RecordWorker.get_maxed_row_arr(associated, fields, @@MAX_ASSOCIATED[association_accessor]) do |field|
          @value_row << field
        end
      end
    end

    def self.get_maxed_row_arr(records, fields, max_count=0, &block)
      return if max_count.nil?
      max_count.times do |i|
        record = records[i].nil? ? {} : RecordWorker.serialized_attributes_for_object_or_class(records[i])
        fields.each do |field|
          val = record[field]
          yield val
        end
      end
    end

    def self.csv_header_prefix_for_key(klass, key, index=nil)
      if klass.respond_to?(:active_model_serializer) && !klass.active_model_serializer.nil? && klass.active_model_serializer.respond_to?(:csv_header_prefix_for_key)
        header_prefix = klass.active_model_serializer.csv_header_prefix_for_key key.to_sym
      else
        header_prefix = klass.to_s
      end

      header_prefix + index.to_s + key.to_s.classify
    end

    def self.serialized_attributes_for_object_or_class(object)
      return {} if object.nil?

      klass, model = object.is_a?(Class) ? [object, object.first] : [object.class, object]

      return {} if model.nil?

      if model.respond_to?(:active_model_serializer) && !model.active_model_serializer.nil?
        serialized = model.active_model_serializer.new(model).as_json(root: false)
      end

      serialized = model.attributes if serialized.nil?
      serialized
    end

    def self.symbolize_options(options)
      options = options.as_json
      if options.is_a? Hash
        options.deep_symbolize_keys!
      elsif options.is_a? Array
        options.map { |val| RecordWorker.symbolize_options val }
      end
    end
  end
end