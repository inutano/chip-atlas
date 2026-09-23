# frozen_string_literal: true

require 'sequel'
require 'sqlite3'

module ChipAtlas
  # SQLite connection settings applied through Sequel's `after_connect` hook
  # so every pooled connection gets them -- including the one each Puma
  # worker opens after `config/puma.rb`'s `before_fork { DB.disconnect }` --
  # not just the connection Sequel happened to open first (LONG-RB-14: a
  # one-shot `DB.run("PRAGMA ...")` right after `Sequel.connect` never
  # reached any later connection).
  #
  # `SQLITE_LOCKING_MODE=EXCLUSIVE` exists for the single-process local dev
  # instance: Docker Desktop's bind-mounted filesystem SIGBUS'd inside
  # sqlite3's mmap of the WAL's `-shm` file (API-54), and exclusive locking
  # mode never creates that file in the first place.
  module DbSettings
    DEFAULT_MMAP_SIZE = 268_435_456 # 256MB memory-mapped I/O
    DEFAULT_LOCKING_MODE = 'NORMAL'
    VALID_LOCKING_MODES = %w[NORMAL EXCLUSIVE].freeze

    module_function

    # SQLITE_MMAP_SIZE env override, in bytes (0 disables mmap). Defaults to
    # DEFAULT_MMAP_SIZE; falls back to it (with a warning) if unset to a
    # non-integer value.
    def mmap_size
      raw = ENV['SQLITE_MMAP_SIZE']
      return DEFAULT_MMAP_SIZE if raw.nil? || raw.empty?

      Integer(raw)
    rescue ArgumentError
      warn "SQLITE_MMAP_SIZE=#{raw.inspect} is not an integer; using default #{DEFAULT_MMAP_SIZE}"
      DEFAULT_MMAP_SIZE
    end

    # SQLITE_LOCKING_MODE env override: 'NORMAL' (default) or 'EXCLUSIVE'.
    # Anything else falls back to the default with a warning.
    def locking_mode
      raw = ENV['SQLITE_LOCKING_MODE']
      return DEFAULT_LOCKING_MODE if raw.nil? || raw.empty?

      normalized = raw.upcase
      return normalized if VALID_LOCKING_MODES.include?(normalized)

      warn "SQLITE_LOCKING_MODE=#{raw.inspect} is invalid (expected NORMAL or EXCLUSIVE); using default #{DEFAULT_LOCKING_MODE}"
      DEFAULT_LOCKING_MODE
    end

    # Effective PRAGMA values, reflecting any environment overrides.
    # Exposed (rather than recomputed ad hoc) so tests and ops tooling can
    # assert what will actually be applied.
    def pragmas
      {
        locking_mode: locking_mode,
        journal_mode: 'WAL',
        synchronous: 'NORMAL',
        cache_size: -64_000, # 64MB cache
        mmap_size: mmap_size,
      }
    end

    # Sequel `after_connect:` hook (arity 1, matching Sequel's non-sharded
    # call convention) that applies `pragmas` to a raw SQLite3::Database
    # connection.
    def after_connect_proc
      method(:apply_pragmas)
    end

    # In-memory databases (no backing file -- `sqlite:/`, `sqlite::memory:`,
    # the test suite's shared fixture DB) have no journal or mmap-able
    # storage, so PRAGMAs are skipped for them, matching the previous
    # rescue-driven behavior. `locking_mode` is set before `journal_mode`:
    # SQLite only skips creating the WAL's `-shm` file when exclusive mode
    # is already in effect at the moment WAL mode is entered.
    def apply_pragmas(conn)
      return if conn.filename.to_s.empty?

      settings = pragmas
      conn.execute("PRAGMA locking_mode=#{settings[:locking_mode]}")
      conn.execute("PRAGMA journal_mode=#{settings[:journal_mode]}")
      conn.execute("PRAGMA synchronous=#{settings[:synchronous]}")
      conn.execute("PRAGMA cache_size=#{settings[:cache_size]}")
      conn.execute("PRAGMA mmap_size=#{settings[:mmap_size]}")
    rescue SQLite3::Exception, Sequel::DatabaseError
      # A PRAGMA failing should never prevent the connection from being usable.
    end
  end
end

unless defined?(DB)
  ENV['DATABASE_URL'] ||= "sqlite://database.sqlite"
  DB = Sequel.connect(ENV['DATABASE_URL'], pool_timeout: 300, after_connect: ChipAtlas::DbSettings.after_connect_proc)
  Sequel.extension :migration
end
