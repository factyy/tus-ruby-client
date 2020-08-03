# frozen_string_literal: true

require 'net/http'
require 'base64'

require_relative 'client/version'

module Tus
  class Client
    # 100 MiB is ok for now...
    CHUNK_SIZE = 100 * 1024 * 1024
    TUS_VERSION = '1.0.0'
    NUM_RETRIES = 5

    def initialize(server_url)
      @server_uri = URI.parse(server_url)

      # better to open the connection now
      @http = Net::HTTP.start(@server_uri.host, @server_uri.port)
      # we cache this value for further use
      @capabilities = capabilities
    end

    def upload(file_path)
      raise 'No such file!' unless File.file?(file_path)

      file_name = File.basename(file_path)
      file_size = File.size(file_path)
      io = File.open(file_path, 'rb')

      upload_by_io(file_name: file_name, file_size: file_size, io: io)
    end

    def upload_by_io(file_name:, file_size:, io:)
      raise 'Cannot upload a stream of unknown size!' unless file_size

      uri = create_remote(file_name, file_size)
      # we use only parameters that are known to the server
      offset, length = upload_parameters(uri)

      chunks = Enumerator.new do |yielder|
        loop do
          chunk = io.read(CHUNK_SIZE)

          break unless chunk

          yielder << chunk
        end
      end

      begin
        offset = chunks.lazy.inject(offset) do |current_offset, chunk|
          upload_chunk(uri, current_offset, chunk)
        end
      rescue StandardError
        raise 'Broken upload! Cannot send a chunk!'
      end

      raise 'Broken upload!' unless offset == length

      io.close
    end

    private

    def capabilities
      raise 'Uninitialized connection!' unless @http

      response = @http.options(@server_uri.request_uri)

      response['Tus-Extension']&.split(',')
    end

    def create_remote(file_name, file_size)
      unless @capabilities.include?('creation')
        raise 'New file uploading is not supported!'
      end

      request = Net::HTTP::Post.new(@server_uri.request_uri)
      request['Content-Length'] = 0
      request['Upload-Length'] = file_size
      request['Tus-Resumable'] = TUS_VERSION
      request['Upload-Metadata'] = "filename: #{Base64.strict_encode64(file_name)},is_confidential"

      response = nil

      NUM_RETRIES.times do
        begin
          response = @http.request(request)
          break
        rescue StandardError
          next
        end
      end

      unless response.is_a?(Net::HTTPCreated)
        raise 'Cannot create a remote file!'
      end

      location_url = response['Location']

      raise 'Malformed server response: missing \'Location\' header' unless location_url

      URI.parse(location_url).path
    end

    def upload_parameters(uri)
      request = Net::HTTP::Head.new(uri)
      request['Tus-Resumable'] = TUS_VERSION

      response = @http.request(request)

      [response['Upload-Offset'], response['Upload-Length']].map(&:to_i)
    end

    def upload_chunk(uri, offset, chunk)
      request = Net::HTTP::Patch.new(uri)
      request['Content-Type'] = 'application/offset+octet-stream'
      request['Upload-Offset'] = offset
      request['Tus-Resumable'] = TUS_VERSION
      request.body = chunk

      response = nil

      NUM_RETRIES.times do
        begin
          response = @http.request(request)
          break
        rescue StandardError
          next
        end
      end

      raise 'Cannot upload a chunk!' unless response.is_a?(Net::HTTPNoContent)

      resulting_offset = response['Upload-Offset'].to_i
      unless resulting_offset == offset + chunk.size
        raise 'Chunk upload is broken!'
      end

      resulting_offset
    end
  end
end
