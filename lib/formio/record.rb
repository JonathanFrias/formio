module Formio
  class Record
    def initialize(formio_hash)
      if formio_hash.empty? || formio_hash.nil?
        raise "cannot construct FormioRecord"
      end
      @_id = @id = formio_hash['_id']
      @form_id = formio_hash['form'] if formio_hash['form']
      @formio_hash = formio_hash
      @form_name = formio_hash['form_name']
      if formio_hash['created']
        @created_at = Time.parse formio_hash['created']
      end
      if formio_hash['modified']
        @updated_at = Time.parse formio_hash['modified']
      end
    end

    def present?
      true
    end

    def to_json
      formio_hash.to_json
    end

    def to_h
      formio_hash
    end

    def [](key)
      formio_hash[key]
    end

    def []=(key, value)
      formio_hash[key] = value
    end

    attr_reader(
      :id,
      :_id,
      :form_id,
      :form_name,
      :created_at,
      :updated_at,
      :formio_hash
      )

    class Nil < Record
      def initialize
        @_id = @id = nil
        @form_id = nil
        @formio_hash = {data: {}}.with_indifferent_access
        @form_name = nil
        @created_at = nil
        @updated_at = nil
      end

      def present?
        false
      end
    end
  end
end
