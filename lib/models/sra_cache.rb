require 'json'

module ChipAtlas
  module SraCache
    TTL_SECONDS = 30 * 24 * 60 * 60  # 30 days

    module_function

    def dataset
      DB[:sra_cache]
    end

    def get(exp_id)
      row = dataset.where(exp_id: exp_id).first
      return nil unless row
      return nil if row[:fetched_at] && (Time.now - row[:fetched_at]) > TTL_SECONDS
      JSON.parse(row[:metadata_json], symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    def set(exp_id, metadata)
      json = JSON.generate(metadata)
      dataset.insert_conflict(
        target: :exp_id,
        update: { metadata_json: json, fetched_at: Time.now }
      ).insert(
        exp_id: exp_id,
        metadata_json: json,
        fetched_at: Time.now,
        created_at: Time.now
      )
    end

    def clear_expired
      cutoff = Time.now - TTL_SECONDS
      dataset.where { fetched_at < cutoff }.delete
    end
  end
end
