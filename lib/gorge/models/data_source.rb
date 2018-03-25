# coding: utf-8

module Gorge
  class DataSource < Sequel::Model
    many_to_one :update_frequency
    many_to_one :server
    one_to_many :data_source_updates
    many_to_one :current_update, class: :'Gorge::DataSourceUpdate', key: :current_update_id

    def process
      @logger = Gorge.logger(program: 'gorge', module_: 'data_source_processing')
      @logger.add_attribute(:name, name)
      @logger.add_attribute(:server, server.name)

      @logger.debug({ msg: 'Starting processing' })

      update(
        current_update: create_data_source_update
      )

      fetch_data
    end

    private
    def create_data_source_update
      add_data_source_update(
        DataSourceUpdate.new(
          state:     :scheduled,
          timestamp: Time.now,
          url:       url
        )
      )
    end

    def fetch_data
      @logger.add_attribute(:url, url)
      current_update.update(
        state: :downloading
      )

      @logger.debug({ msg: 'Downloading data file' })
      download_started_at = Time.now
      request = Typhoeus::Request.new(
        url,
        accept_encoding: 'gzip',
        connecttimeout: Config::DataImport::HTTP_CONNECT_TIMEOUT,
      )

      result = false
      buffer = output_file

      request.on_body do |chunk|
        buffer.write(chunk)
      end

      request.on_complete do |response|
        buffer.close

        result = if response.success?
                   download_success(Time.now - download_started_at, buffer.path)

                   true
                 elsif response.timed_out?
                   download_error 'Timeout while connecting'
                 elsif response.code == 0
                   # Non-HTTP error
                   download_error "Error while downloading: #{ response.return_message }"
                 else
                   # HTTP error
                   download_error "Non-success status code received: #{ response.code }"
                 end
        @logger.remove_attribute :url
      end

      request.run

      return result

    rescue Exception => e
      buffer.close if buffer
      download_exception(e)
      raise
    end

    def download_success(time_taken, file_path)
      @logger.debug({ msg: 'Sucessfully downloaded', download_time: time_taken })
      current_update.update(
        download_time: time_taken,
        file_path: file_path
      )

      true
    end

    def download_error(msg)
      @logger.error({ msg: msg, success: false })
      current_update.update(
        state:         :downloading_failed,
        error_message: msg,
      )

      false
    end

    def download_exception(e)
      msg = "Unhandled #{ e.class } while downloading: #{ e.message }"
      @logger.error({ msg: msg })
      current_update.update(
        state: :failed,
        error_message: msg
      )

      false
    end

    def output_file
      file_name = [
        server.name,
        name,
        Time.now.strftime('%Y%m%d_%H%M%S'),
      ].join('_').downcase.gsub(/\s/, '_')
      file_name << '.sqlite3'

      path = File.join(Config::DataImport::STORAGE_PATH, file_name)
      File.open(path, 'wb')
    end
  end
end
