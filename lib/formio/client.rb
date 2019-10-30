module Faraday
  module Utils
    def escape(str)
      str.to_s.gsub(ESCAPE_RE) do |match|
        '%' + match.unpack('H2' * match.bytesize).join('%').upcase
      end.gsub(' ', '%20')
    end
  end
end

class Formio::Client
  def initialize(project_url, email: nil, password: nil, auth_token: nil)
    @project_url = project_url
    @email = email
    @password = password
    @auth_token = auth_token
    login if email.present? && password.present?
  end

  def first(form)
    index(form, limit: 1, skip: 0)[0]
  end

  def index(form, limit: '1000', skip: '0', sort: '-created', params: {})
    response = connection.get do |req|
      req.url "/#{form}/submission"
      req.params = params.merge({
        limit: limit,
        skip: skip,
        sort: sort
      })
      set_headers(req)
    end
    parse_response(response.body).map do |formio_hash|
      Formio::Record.new(formio_hash)
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
      Formio::Record.new(parse_response(response.body))
    else
      parse_response(response.body)['details'].map { |x| x['message'] }
    end
  end

  def update(record, max_depth: 2)
    raise "Must supply a formio form" unless record.is_a?(Formio::Record)
    response = connection.put do |req|
      req.url "/#{record.form_name}/submission/#{record.id}"
      req.url "/form/#{record.form_id}/submission/#{record.id}" if record.form_id
      set_headers(req)
      req.body = compact_formio_hash(record.formio_hash, max_depth).to_json
    end

    return update(record) if response.status == 502
    if response.status >= 200 && response.status < 300
      Formio::Record.new(parse_response(response.body))
    else
      parse_response(response.body)['details'].map { |x| x['message'] }
    end

  rescue Net::OpenTimeout
    retry
  end

  def update_patch(form_name, id, patch_array)
    response = connection.patch do |req|
      req.url "/#{form_name}/submission/#{id}"
      set_headers(req)
      req.body = patch_array.to_json
    end
  end

  def find_by_id(form, submission_id)
    raise "No submission_id provided" if submission_id.nil?
    response = connection.get do |req|
      req.url "/#{form}/submission/#{submission_id}"
      set_headers(req)
    end
    return find_by_id form, submission_id if response.status == 502
    if response.status == 200
      Formio::Record.new(parse_response(response.body))
    else
      Formio::Record::Nil.new
    end
  end

  def filter_by(form, values={})
    # Look at api to implement this
    raise "Not implemented yet!"
  end

  def find_by(form, values={})
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
      Formio::Record::Nil.new
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
      req.params['limit'] = '1000'
    end
    response = parse_response(response.body)
    if response.is_a?(Array)
      return response.map do |f|
        ::Formio::Form.new f
      end
    end
    ::Formio::Form.new(response)
  end

  def create_form(formio_form)
    raise "Must supply a formio form" unless formio_form.is_a?(::Formio::Form)
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

  def update_form(formio_form)
    raise "Must supply a formio form" unless formio_form.is_a?(::Formio::Form)
    response = connection.put do |req|
      req.url "/form/#{formio_form.id}"
      set_headers(req)
      req.body = formio_form.to_json
    end
    if response.status >= 200 && response.status < 300
      parse_response(response.body)
    else
      raise "error updating form."
    end
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
        puts stringio.rewind.to_s
        puts "An issue occured with formio: #{response}"
      # rescue e
      #   puts "An issue occured with formio #{response}"
      end
    }

    response
      .try { |it| StringIO.new(it) }
      .try { |stringio| read_gzip_data.call(stringio) }
      .try { |reader| reader.read }
      .try { |json_string| JSON.parse(json_string) }
      .yield_self { |parsed_json| parsed_json || [] }
  end

  def connection
    require 'faraday/detailed_logger'
    @connection ||= Faraday::Connection.new(project_url,
      ssl: { verify: true }
    ) do |builder|
      require 'faraday_curl'
      # require 'faraday-detailed_logger'
      require 'faraday-cookie_jar'
      builder.request  :multipart
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
    return Formio::Record::Nil.new unless response.status >= 200 && response.status < 300
    Formio::Record.new(parse_response(response.body))
  end

  def login
    try_user || try_owner
  end

  def try_user
    try_login(project_url)
  end

  def try_owner
    try_login("https://formio.form.io/user/login/submission")
  end

  def try_login(url)
    @auth_token ||= begin
      return unless email
      formio_conn = Faraday::Connection.new(url, ssl: { verify: true })

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
  alias auth_token login

  attr_reader :email, :password, :project_url

  def compact_formio_hash(data, max_level=2)
    return unless data.is_a?(Hash) || data.is_a?(Array)
    data.each do |k,v|
      if max_level <= 0
        data.delete k
      else
        if(v.is_a?(Hash))
          compact_formio_hash(v, max_level - 1)
        end
        if(v.is_a?(Array))
          v.each { |elem| compact_formio_hash(elem, max_level) }
        end
      end
    end.compact
  end

  def roles
    response = connection.get do |req|
      # req.url "/#{form}/submission?limit=#{limit}&skip=#{skip}&sort=#{sort}"
      req.url "/access"
      set_headers(req)
    end
    parse_response(response.body)
  end
end
