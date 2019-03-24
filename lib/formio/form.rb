module Formio
  class Form
    attr_accessor(
      :formio_hash,
      :type,
      :formio_id,
      :components,
      :name,
      :title,
      :path,
      :submission_access,
      :created_at,
      :updated_at
    )

    def initialize(formio_hash)
      @formio_hash = formio_hash
      @type = formio_hash['type']
      @formio_id = formio_hash['_id']
      @components = formio_hash['components']
      @name = @title = formio_hash['title']
      @path = formio_hash['path']
      @created_at = DateTime.parse formio_hash['created']
      @updated_at = DateTime.parse formio_hash['modified']
      @submission_access = formio_hash['submissionAccess']
    end

    def name=(name)
      @name = @title = name
    end
    
    def title=(title)
      @name = @title = title
    end

    def id
      formio_hash['_id']
    end

    def to_h
      formio_hash
    end

    def to_json
      to_h.to_json
    end
  end
end