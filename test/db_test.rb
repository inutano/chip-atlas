# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/db'
require 'tmpdir'

# Regression coverage for two 2026-09-23 review findings:
#
# - LONG-RB-14: `lib/db.rb` used to run its PRAGMAs once via `DB.run(...)`
#   right after the first `Sequel.connect`, so only that one connection ever
#   got them -- every other pooled connection (and every Puma worker's
#   post-fork reconnection) silently ran with SQLite defaults instead.
# - API-54: the local Docker Desktop dev instance SIGBUS'd inside sqlite3's
#   mmap of the WAL `-shm` file on a bind-mounted database. Exclusive
#   locking mode never creates that file, so it needs to be reachable via an
#   env var for that single-process dev setup without changing production
#   defaults.
#
# This uses its own Dir.mktmpdir-backed Sequel connections throughout --
# never the app's global DB constant -- so it stays safe under
# `script/dev/test.sh` (--network none) and never touches database.sqlite*.
class DbSettingsTest < Minitest::Test
  def test_default_pragmas_are_applied_on_connect
    with_env('SQLITE_LOCKING_MODE' => nil, 'SQLITE_MMAP_SIZE' => nil) do
      with_tmp_db do |db|
        assert_equal 'normal', pragma(db, 'locking_mode')
        assert_equal 'wal', pragma(db, 'journal_mode')
        assert_equal 268_435_456, pragma(db, 'mmap_size')
      end
    end
  end

  def test_env_overrides_are_applied_to_a_genuinely_second_pooled_connection
    # NORMAL locking here (WAL's normal multi-reader mode), so two
    # connections can legitimately be open at once. SQLITE_LOCKING_MODE=
    # EXCLUSIVE is covered separately below via a reconnect instead: two
    # *simultaneous* exclusive-mode connections are a contradiction in
    # terms (confirmed live: the second gets SQLite3::BusyException --
    # that is the documented trade-off of never mapping the -shm file).
    with_env('SQLITE_LOCKING_MODE' => 'NORMAL', 'SQLITE_MMAP_SIZE' => '0') do
      with_tmp_db(max_connections: 2) do |db|
        db.pool.hold do |first_conn|
          assert_equal 'normal', first_conn.execute('PRAGMA locking_mode').first.first
          assert_equal 'wal', first_conn.execute('PRAGMA journal_mode').first.first
          assert_equal 0, first_conn.execute('PRAGMA mmap_size').first.first

          # First connection is still checked out, so this forces the pool
          # to open a genuinely separate second connection -- exactly the
          # case LONG-RB-14 found unpatched (only the first connection
          # Sequel happened to open ever got the PRAGMAs).
          second_conn = nil
          Thread.new { db.synchronize { |c| second_conn = c } }.join

          refute_same first_conn, second_conn, 'expected a distinct second pooled connection'
          assert_equal 'normal', second_conn.execute('PRAGMA locking_mode').first.first
          assert_equal 'wal', second_conn.execute('PRAGMA journal_mode').first.first
          assert_equal 0, second_conn.execute('PRAGMA mmap_size').first.first
        end
      end
    end
  end

  # SQLITE_LOCKING_MODE=EXCLUSIVE (the API-54 dev-instance override) makes
  # SQLite refuse a second *simultaneous* connection outright, so the
  # regression this override still has to survive is a *sequential*
  # reconnect: config/puma.rb's `before_fork { DB.disconnect }` closes every
  # pooled connection and each Puma worker then opens fresh ones after
  # forking, exactly like `db.disconnect` below.
  def test_exclusive_locking_mode_is_reapplied_after_a_reconnect
    with_env('SQLITE_LOCKING_MODE' => 'EXCLUSIVE', 'SQLITE_MMAP_SIZE' => '0') do
      with_tmp_db do |db|
        assert_equal 'exclusive', pragma(db, 'locking_mode')
        assert_equal 'wal', pragma(db, 'journal_mode')
        assert_equal 0, pragma(db, 'mmap_size')

        db.disconnect
        assert_equal 'exclusive', pragma(db, 'locking_mode')
        assert_equal 'wal', pragma(db, 'journal_mode')
        assert_equal 0, pragma(db, 'mmap_size')
      end
    end
  end

  def test_invalid_locking_mode_env_falls_back_to_normal_with_a_warning
    with_env('SQLITE_LOCKING_MODE' => 'bogus', 'SQLITE_MMAP_SIZE' => nil) do
      _, stderr = capture_io { with_tmp_db { |db| assert_equal 'normal', pragma(db, 'locking_mode') } }
      assert_match(/SQLITE_LOCKING_MODE/, stderr)
    end
  end

  def test_invalid_mmap_size_env_falls_back_to_default_with_a_warning
    with_env('SQLITE_LOCKING_MODE' => nil, 'SQLITE_MMAP_SIZE' => 'not-a-number') do
      _, stderr = capture_io { with_tmp_db { |db| assert_equal 268_435_456, pragma(db, 'mmap_size') } }
      assert_match(/SQLITE_MMAP_SIZE/, stderr)
    end
  end

  private

  def pragma(db, name)
    db.synchronize { |c| c.execute("PRAGMA #{name}").first.first }
  end

  def with_tmp_db(max_connections: nil)
    Dir.mktmpdir do |dir|
      opts = { after_connect: ChipAtlas::DbSettings.after_connect_proc }
      opts[:max_connections] = max_connections if max_connections
      db = Sequel.connect("sqlite://#{File.join(dir, 'test.sqlite')}", **opts)
      yield db
    ensure
      db&.disconnect
    end
  end

  def with_env(overrides)
    original = {}
    overrides.each_key { |k| original[k] = ENV[k] }
    overrides.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
