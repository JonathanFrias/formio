module Formio
  class Client
    def initialize(project_url, email: nil, password: nil, auth_token: nil)
      @project_url = project_url
      @email = email
      @password = password
      @auth_token = auth_token
      login if email.present? && password.present?
    end

    def index(form)
      response = connection.get do |req|
        req.url "/#{form}/submission?limit=1000000&skip=0&sort=-created"
        set_headers(req)
      end
      parse_response(response.body).map do |formio_hash|
        FormioRecord.new(formio_hash)
      end
    end

    def create(form:, values:)
      values.each do |(k,_)|
        values[k] ||= ""
      end
      response = connection.post do |req|
        req.url "/#{form}/submission/"
        set_headers(req)
        req.body = {
          data: values
        }.to_json
      end
      if response.status >= 200 && response.status < 300
        FormioRecord.new(parse_response(response.body))
      else
        parse_response(response.body)['details'].map { |x| x['message'] }
      end
    end

    def update(record)
      raise "Must supply a formio form" unless record.is_a?(FormioRecord)
      response = connection.put do |req|
        req.url "/#{record.form_name}/submission/#{record.id}"
        req.url "/form/#{record.form_id}/submission/#{record.id}" if record.form_id
        set_headers(req)
        req.body = record.to_json
      end

      return update(record) if response.status == 502
      if response.status >= 200 && response.status < 300
        FormioRecord.new(parse_response(response.body))
      else
        parse_response(response.body)['details'].map { |x| x['message'] }
      end
    end

    def find_by_id(form, submission_id)
      response = connection.get do |req|
        req.url "/#{form}/submission/#{submission_id}"
        set_headers(req)
      end
      return find_by_id form, submission_id if response.status == 502
      if response.status == 200
        FormioRecord.new(parse_response(response.body))
      else
        FormioRecord::Nil.new
      end
    end

    def find_by(form, values=[])
      response = connection.get do |req|
        req.url "/#{form}/exists"
        set_headers(req)
        values.each do |(k,v)|
          k = 'data.' + k.to_s unless k.to_s.start_with?('data.')
          req.params[k] = v
        end
      end
      return find_by(form, values) if response.status == 502
      if response.status == 200
        return find_by_id(form, JSON.parse(response.body)['_id'])
      else
        FormioRecord::Nil.new
      end
    end

    def delete(form, submission_id)
      response = connection.delete do |req|
        req.url "/#{form}/submission/#{submission_id}"
        set_headers(req)
      end
      response.status == 200
    end

    def form_meta_data(form = 'form')
      response = connection.get do |req|
        req.url "/#{form}"
        set_headers(req)
      end
      response = parse_response(response.body)
      if response.is_a?(Array)
        return response.map do |f|
          FormioForm.new f
        end
      end
      FormioForm.new(response)
    end

    def create_form(formio_form)
      raise "Must supply a formio form" unless formio_form.is_a?(FormioForm)
      response = connection.post do |req|
        req.url "/form"
        set_headers(req)
        req.body = formio_form.to_json
      end
      if response.status != 201
        raise (JSON.parse(response.body)['message'])
      end
      true
    end

    def delete_form(form_name)
      response = connection.delete do |req|
        req.url "/#{form_name}"
        set_headers(req)
      end
      response.status == 200 || response.body == 'Invalid alias'
    end

    def set_headers(req)
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept'] = 'application/json'
      req.headers['x-jwt-token'] = auth_token
    end

    def parse_response(response)
      # return early if it's already valid json
      # Some requests simply return json, some
      # have to be decoded
      begin
        return JSON.parse(response)
      rescue JSON::ParserError
      end

      read_gzip_data = -> (stringio) {
        begin
          Zlib::GzipReader.new(stringio, encoding: 'ASCII-8BIT')
        rescue Zlib::GzipFile::Error
          puts "An issue occured with formio: #{response}"
        rescue
          puts "An issue occured with formio"
        end
      }

      response
        .try { |it| StringIO.new(it) }
        .try { |stringio| read_gzip_data.call(stringio) }
        .try { |reader| reader.read }
        .try { |json_string| JSON.parse(json_string) }
        .yield_self { |parsed_json| parsed_json || [] } # casts to empty array if anything went wrong
    end

    def connection
      require 'faraday/detailed_logger'
      @connection ||= Faraday::Connection.new(project_url,
        ssl: { verify: true }
      ) do |builder|
        # builder.request  :multipart
        # builder.use ::FaradayMiddleware::ParseJson, content_type: 'application/json'
        # builder.request  :url_encoded
        builder.request :curl
        builder.adapter  :net_http
        # builder.response :detailed_logger # <-- Inserts the logger into the connection.
      end
    end

    def current_user
      response = connection.get do |req|
        req.url '/current'
        set_headers(req)
      end
      FormioRecord.new(parse_response(response.body))
    end

    def login
      @auth_token ||= begin
        Rails.cache.fetch("formio_login" + email, expires_in: 12.hours) do
          formio_conn = Faraday::Connection.new("https://formio.form.io", ssl: { verify: true })

          login_response = formio_conn.post do |req|
            req.url "/user/login"
            req.headers['Content-Type'] = 'application/json'
            req.headers['Accept'] = 'application/json'
            req.body = {
              data: {
                email: email,
                password: password
              }
            }.to_json
          end
          login_response.headers['x-jwt-token']
        end
      end
    end
    alias auth_token login

    private
    attr_reader :email, :password, :project_url
  end
end