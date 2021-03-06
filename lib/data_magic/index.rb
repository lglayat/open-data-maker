require 'forwardable'

require_relative 'config'
require_relative 'index/builder_data'
require_relative 'index/event_logger'
require_relative 'index/document'
require_relative 'index/document_builder'
require_relative 'index/importer'
require_relative 'index/output'
require_relative 'index/repository'
require_relative 'index/row_importer'
require_relative 'index/super_client'

require 'action_view'  # for distance_of_time_in_words (logging time)
include ActionView::Helpers::DateHelper  # for distance_of_time_in_words (logging time)

module DataMagic
  # data could be a String or an io stream
  def self.import_csv(data, options={})
    Index::Importer.process(data, options)
  end

  # pre-condition: index is already created w/ config
  def self.index_with_dictionary(options = {})
    start_time = Time.now
    Config.logger.debug "--- index_with_dictionary, starting at #{start_time}"

    logger.info "files: #{self.config.files}"

    # optionally continue importing from a named file (see import.rake)
    starting_from = 0
    if options[:continue]
      starting_from = config.files.find_index { |file| file.match( /#{options[:continue]}/ ) }
      logger.info "Indexing continues with file: #{options[:continue]}" unless starting_from.nil?
    end

    config.files[starting_from.to_i..-1].each_with_index do |filepath, index|
      fname = filepath.split('/').last
      logger.debug "indexing #{fname} #{starting_from + index} file config:#{config.additional_data_for_file(starting_from + index).inspect}"
      options[:add_data] = config.additional_data_for_file(starting_from + index)
      options[:only] = config.info_for_file(starting_from + index, :only)
      options[:nest] = config.info_for_file(starting_from + index, :nest)
      begin
        logger.debug "--"*40
        logger.debug "--    #{filepath}"
        logger.debug "--"*40
        file_start = Time.now
        data = config.read_path(filepath)
        rows, _ = DataMagic.import_csv(data, options)
        file_end = Time.now
        logger.debug "imported #{rows} rows in #{distance_of_time_in_words(file_end, file_start)}, ms: #{file_end - file_start}"
      rescue DataMagic::InvalidData => e
       Config.logger.debug "Error: skipping #{filepath}, #{e.message}"
      end
    end
    end_time = Time.now
    logger.debug "indexing complete: #{distance_of_time_in_words(end_time, start_time)}"
    logger.debug "duration: #{end_time - start_time}"
  end

  def self.import_with_dictionary(options = {})
    #logger.debug("field_mapping: #{field_mapping.inspect}")
    options[:mapping] = config.field_mapping
    options = options.merge(config.options)

    es_index_name = self.config.load_datayaml(options[:data_path])
    unless config.index_exists?(es_index_name)
      logger.info "creating #{es_index_name}"   # TO DO: fix #14
      create_index es_index_name, config.field_types
    end

    index_with_dictionary(options)

  end # import_with_dictionary

private
  def self.valid_types
    %w[integer float string literal name autocomplete boolean]
  end

end # module DataMagic
