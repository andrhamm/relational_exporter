require 'celluloid'

module RelationalExporter
  class CsvBuilder
    include Celluloid
    include Celluloid::Logger

    attr_accessor :queue, :end_index

    trap_exit :actor_died
    def actor_died(actor, reason)
      warn "Oh no! #{actor.inspect} has died because of a #{reason.class}" unless reason.nil?
    end

    def initialize(file_path=nil)
      @header_row = []
      @index = 0
      @end_index = nil
      @queue = {}
      @file_path = file_path
    end

    def start
      csv_args = @file_path.blank? ? STDOUT : @file_path

      csv_options = {headers: true}
      if @file_path.blank?
        csv_method = :instance
        csv_args = [STDOUT, csv_options]
      else
        csv_method = :open
        csv_args = [@file_path, 'wb', csv_options]
      end

      ::CSV.send(csv_method, *csv_args) do |csv|
        until @index == @end_index
          if row = @queue.delete(@index)
            write_row(row, csv)
            @index += 1
          else
            sleep 1
          end
        end
      end

      true
    end

    def remaining
      @end_index - @index if @end_index
    end

    private

    def write_row(row, csv)
      headers, values = row.is_a?(Celluloid::Future) ? row.value : row
      if csv.header_row?
        @header_row = headers
        info "Writing headers to file (#{headers.count})"
        csv << @header_row
      end
      if values.count == @header_row.count
        info "Writing row to file (#{@index})"
        csv << values
      else
        # @logger.error "Encountered invalid row, skipping."
        error "Bad row! #{values.count} vs #{@header_row.count}", @header_row.join(','), values.join(',')
      end
    end
  end
end