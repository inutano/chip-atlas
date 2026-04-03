# Backend Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current ActiveRecord-based Sinatra backend with a Sequel-based backend that passes all existing API smoke tests while using clean snake_case internals.

**Architecture:** Sinatra app with Sequel ORM connecting to SQLite. Routes organized by feature into separate files. Models in `lib/models/`, services in `lib/services/`. All API JSON responses preserve camelCase field names for backward compatibility. FTS5 for full-text search with server-side pagination (no more big JSON dump).

**Tech Stack:** Ruby 3.2.2, Sinatra 4.x, Sequel, SQLite3, FTS5, Minitest, Rack::Test

**Reference:** Design spec at `SHIKINEN-SENGU.md`, current app at `app.rb` (506 lines), models at `lib/pj/` (9 files, ~1,098 lines)

---

## File Structure

```
chip-atlas/
├── app.rb                          # NEW: Slim entry point (~30 lines)
├── config.ru                       # MODIFY: Point to new app
├── Gemfile                         # MODIFY: Sequel replaces AR
├── Rakefile                        # MODIFY: Sequel tasks
├── config/
│   └── database.yml                # MODIFY: Sequel config
├── db/
│   ├── migrations/
│   │   └── 001_create_schema.rb    # NEW: Clean Sequel schema
│   └── database.sqlite             # GENERATED: By migrations + rake
├── lib/
│   ├── chip_atlas.rb               # NEW: Module loader (replaces lib/pj.rb)
│   ├── models/
│   │   ├── experiment.rb           # NEW: Sequel model
│   │   ├── experiment_search.rb    # NEW: FTS5 search
│   │   ├── bedfile.rb              # NEW: Sequel model
│   │   ├── bedsize.rb              # NEW: Sequel model
│   │   ├── analysis.rb             # NEW: Sequel model
│   │   ├── run.rb                  # NEW: Sequel model
│   │   └── sra_cache.rb            # NEW: SRA metadata cache
│   ├── services/
│   │   ├── location_service.rb     # NEW: URL generation
│   │   ├── wabi_service.rb         # NEW: DDBJ job submission
│   │   └── sra_service.rb          # NEW: NCBI metadata fetch + cache
│   ├── serializers.rb              # NEW: snake_case → camelCase
│   └── tasks/
│       └── metadata.rake           # NEW: Sequel-based loading
├── routes/
│   ├── api.rb                      # NEW: JSON API endpoints
│   ├── pages.rb                    # NEW: HTML page routes (stubs)
│   ├── wabi.rb                     # NEW: WABI proxy routes
│   └── health.rb                   # NEW: Health check
└── test/
    ├── test_helper.rb              # NEW: Minitest + Rack::Test setup
    ├── models/
    │   ├── experiment_test.rb      # NEW
    │   ├── bedfile_test.rb         # NEW
    │   └── experiment_search_test.rb # NEW
    ├── services/
    │   └── location_service_test.rb  # NEW
    ├── routes/
    │   ├── api_test.rb             # NEW
    │   └── health_test.rb          # NEW
    └── smoke_test.sh               # MODIFY: Updated paths
```

---

### Task 1: Gemfile and Dependencies

**Files:**
- Modify: `Gemfile`
- Create: `.ruby-version`

- [ ] **Step 1: Write new Gemfile**

Replace the current Gemfile. Remove AR, HAML, sass-embedded, net-ping, rubyzip. Add Sequel, erubi, minitest, rack-test.

```ruby
# Gemfile
source 'https://rubygems.org'

# Web framework
gem 'sinatra'
gem 'rackup'
gem 'rack-protection'
gem 'unicorn'

# Database
gem 'sequel'
gem 'sqlite3'

# Templates & rendering
gem 'erubi'
gem 'tilt'
gem 'redcarpet'

# Utilities
gem 'nokogiri'
gem 'rake'

group :test do
  gem 'minitest'
  gem 'rack-test'
end
```

- [ ] **Step 2: Update .ruby-version**

```
3.2.2
```

- [ ] **Step 3: Run bundle install**

Run: `bundle install`
Expected: Successful install with fewer gems than before

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock .ruby-version
git commit -m "Replace ActiveRecord with Sequel, trim dependencies

Removed: activerecord, sinatra-activerecord, haml, sass-embedded,
net-ping, rubyzip, webrick
Added: sequel, erubi, minitest, rack-test"
```

---

### Task 2: Database Schema (Sequel Migration)

**Files:**
- Create: `db/migrations/001_create_schema.rb`

- [ ] **Step 1: Write the Sequel migration**

This creates the clean schema with snake_case columns, composite indexes, and the sra_cache table. FTS5 virtual table is created via raw SQL since Sequel doesn't have native FTS5 support.

```ruby
# db/migrations/001_create_schema.rb
Sequel.migration do
  up do
    create_table :experiments do
      primary_key :id
      String :exp_id, null: false
      String :genome, null: false
      String :ag_class
      String :ag_sub_class
      String :cl_class
      String :cl_sub_class
      String :cl_sub_class_info
      String :read_info
      String :title
      String :attributes, text: true
      DateTime :created_at

      index :exp_id
      index :genome
      index :ag_class
      index :ag_sub_class
      index :cl_class
      index :cl_sub_class
      index [:genome, :ag_class]
      index [:genome, :ag_class, :cl_class]
    end

    create_table :bedfiles do
      primary_key :id
      String :filename, null: false
      String :genome, null: false
      String :ag_class
      String :ag_sub_class
      String :cl_class
      String :cl_sub_class
      String :qval
      String :experiments, text: true
      DateTime :created_at

      index :genome
      index [:genome, :ag_class, :ag_sub_class, :cl_class, :cl_sub_class, :qval],
            name: :idx_bedfiles_lookup
    end

    create_table :bedsizes do
      primary_key :id
      String :genome, null: false
      String :ag_class
      String :cl_class
      String :qval
      Bignum :number_of_lines
      DateTime :created_at

      index [:genome, :ag_class, :cl_class, :qval], name: :idx_bedsizes_lookup
    end

    create_table :analyses do
      primary_key :id
      String :antigen
      String :cell_list, text: true
      TrueClass :target_genes
      String :genome, null: false
      DateTime :created_at

      index :antigen
      index :genome
      index :target_genes
    end

    create_table :runs do
      primary_key :id
      String :run_id, null: false
      String :exp_id, null: false
      DateTime :created_at

      index :run_id
      index :exp_id
    end

    create_table :sra_cache do
      primary_key :id
      String :exp_id, null: false, unique: true
      String :metadata_json, text: true
      DateTime :fetched_at
      DateTime :created_at
    end

    # FTS5 virtual table for full-text search
    run <<-SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS experiments_fts USING fts5(
        exp_id,
        sra_id,
        geo_id,
        genome,
        ag_class,
        ag_sub_class,
        cl_class,
        cl_sub_class,
        title,
        attributes
      );
    SQL
  end

  down do
    run "DROP TABLE IF EXISTS experiments_fts"
    drop_table :sra_cache
    drop_table :runs
    drop_table :analyses
    drop_table :bedsizes
    drop_table :bedfiles
    drop_table :experiments
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add db/migrations/001_create_schema.rb
git commit -m "Add Sequel migration with clean snake_case schema"
```

---

### Task 3: Test Helper and Database Setup

**Files:**
- Create: `test/test_helper.rb`

- [ ] **Step 1: Write test helper**

Sets up Minitest, Rack::Test, and an in-memory SQLite database for testing.

```ruby
# test/test_helper.rb
ENV['RACK_ENV'] = 'test'
ENV['DATABASE_URL'] = 'sqlite:/'  # In-memory database for tests

require 'minitest/autorun'
require 'rack/test'
require 'sequel'
require 'json'

# Connect to in-memory DB and run migrations
DB = Sequel.connect(ENV['DATABASE_URL'])
Sequel::Migrator.run(DB, File.join(__dir__, '..', 'db', 'migrations'))

# Load models after DB is connected
require_relative '../lib/chip_atlas'

module TestHelper
  def seed_experiments
    DB[:experiments].multi_insert([
      { exp_id: 'SRX018625', genome: 'hg38', ag_class: 'Histone',
        ag_sub_class: 'H3K4me3', cl_class: 'Blood', cl_sub_class: 'K-562',
        cl_sub_class_info: '', read_info: '15000000,50', title: 'H3K4me3 in K-562',
        attributes: 'cell line', created_at: Time.now },
      { exp_id: 'SRX018626', genome: 'hg38', ag_class: 'TFs and others',
        ag_sub_class: 'CTCF', cl_class: 'Blood', cl_sub_class: 'K-562',
        cl_sub_class_info: '', read_info: '20000000,50', title: 'CTCF in K-562',
        attributes: 'cell line', created_at: Time.now },
      { exp_id: 'SRX100001', genome: 'hg38', ag_class: 'Histone',
        ag_sub_class: 'H3K27ac', cl_class: 'Brain', cl_sub_class: 'Neuron',
        cl_sub_class_info: '', read_info: '10000000,75', title: 'H3K27ac in Neuron',
        attributes: 'primary cell', created_at: Time.now },
      { exp_id: 'SRX100002', genome: 'mm10', ag_class: 'ATAC-Seq',
        ag_sub_class: '-', cl_class: 'Liver', cl_sub_class: 'Hepatocyte',
        cl_sub_class_info: '', read_info: '8000000,150', title: 'ATAC-seq in Hepatocyte',
        attributes: 'primary cell', created_at: Time.now },
    ])
  end

  def seed_bedfiles
    DB[:bedfiles].multi_insert([
      { filename: 'H3K4me3.Blood.05', genome: 'hg38', ag_class: 'Histone',
        ag_sub_class: 'H3K4me3', cl_class: 'Blood', cl_sub_class: '-',
        qval: '05', experiments: 'SRX018625', created_at: Time.now },
      { filename: 'H3K4me3.ALL.05', genome: 'hg38', ag_class: 'Histone',
        ag_sub_class: 'H3K4me3', cl_class: 'All cell types', cl_sub_class: '-',
        qval: '05', experiments: 'SRX018625,SRX100001', created_at: Time.now },
    ])
  end

  def seed_analyses
    DB[:analyses].multi_insert([
      { antigen: 'CTCF', cell_list: 'K-562,HeLa-S3,GM12878',
        target_genes: true, genome: 'hg38', created_at: Time.now },
      { antigen: 'H3K4me3', cell_list: 'K-562,Neuron',
        target_genes: false, genome: 'hg38', created_at: Time.now },
    ])
  end

  def seed_bedsizes
    DB[:bedsizes].multi_insert([
      { genome: 'hg38', ag_class: 'Histone', cl_class: 'Blood',
        qval: '05', number_of_lines: 150000, created_at: Time.now },
      { genome: 'hg38', ag_class: 'Histone', cl_class: 'Brain',
        qval: '05', number_of_lines: 80000, created_at: Time.now },
    ])
  end

  def seed_all
    seed_experiments
    seed_bedfiles
    seed_analyses
    seed_bedsizes
  end

  def teardown
    DB[:experiments].delete
    DB[:bedfiles].delete
    DB[:bedsizes].delete
    DB[:analyses].delete
    DB[:runs].delete
    DB[:sra_cache].delete
    DB.run("DELETE FROM experiments_fts")
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add test/test_helper.rb
git commit -m "Add test helper with in-memory SQLite and seed data"
```

---

### Task 4: Serializer (snake_case to camelCase)

**Files:**
- Create: `lib/serializers.rb`
- Create: `test/serializers_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/serializers_test.rb
require_relative 'test_helper'
require_relative '../lib/serializers'

class SerializersTest < Minitest::Test
  def test_experiment_serializer
    row = { exp_id: 'SRX018625', genome: 'hg38', ag_class: 'Histone',
            ag_sub_class: 'H3K4me3', cl_class: 'Blood', cl_sub_class: 'K-562',
            title: 'H3K4me3 in K-562', attributes: 'cell line',
            read_info: '15000000,50', cl_sub_class_info: 'ATCC' }

    result = ChipAtlas::Serializers.experiment(row)

    assert_equal 'SRX018625', result[:expid]
    assert_equal 'hg38', result[:genome]
    assert_equal 'Histone', result[:agClass]
    assert_equal 'H3K4me3', result[:agSubClass]
    assert_equal 'Blood', result[:clClass]
    assert_equal 'K-562', result[:clSubClass]
    assert_equal 'H3K4me3 in K-562', result[:title]
    assert_equal 'cell line', result[:attributes]
    assert_equal '15000000,50', result[:readInfo]
    assert_equal 'ATCC', result[:clSubClassInfo]
  end

  def test_classification_item_serializer
    result = ChipAtlas::Serializers.classification_item('Blood', 120)
    assert_equal({ id: 'Blood', label: 'Blood', count: 120 }, result)
  end

  def test_search_result_serializer
    fts_row = { 'exp_id' => 'SRX018625', 'sra_id' => 'SRA123',
                'geo_id' => 'GSM456', 'genome' => 'hg38',
                'ag_class' => 'Histone', 'ag_sub_class' => 'H3K4me3',
                'cl_class' => 'Blood', 'cl_sub_class' => 'K-562',
                'title' => 'test', 'attributes' => 'cell line' }

    result = ChipAtlas::Serializers.search_result(fts_row)

    assert_equal 'SRX018625', result[:expid]
    assert_equal 'SRA123', result[:sra_id]
    assert_equal 'GSM456', result[:geo_id]
    assert_equal 'Histone', result[:agClass]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/serializers_test.rb`
Expected: FAIL - `ChipAtlas::Serializers` not defined

- [ ] **Step 3: Write implementation**

```ruby
# lib/serializers.rb
module ChipAtlas
  module Serializers
    module_function

    def experiment(row)
      {
        expid:          row[:exp_id],
        genome:         row[:genome],
        agClass:        row[:ag_class],
        agSubClass:     row[:ag_sub_class],
        clClass:        row[:cl_class],
        clSubClass:     row[:cl_sub_class],
        title:          row[:title],
        attributes:     row[:attributes],
        readInfo:       row[:read_info],
        clSubClassInfo: row[:cl_sub_class_info],
      }
    end

    def classification_item(id, count = nil)
      { id: id, label: id, count: count }
    end

    def search_result(fts_row)
      {
        expid:      fts_row['exp_id'],
        sra_id:     fts_row['sra_id'],
        geo_id:     fts_row['geo_id'],
        genome:     fts_row['genome'],
        agClass:    fts_row['ag_class'],
        agSubClass: fts_row['ag_sub_class'],
        clClass:    fts_row['cl_class'],
        clSubClass: fts_row['cl_sub_class'],
        title:      fts_row['title'],
        attributes: fts_row['attributes'],
      }
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby test/serializers_test.rb`
Expected: 3 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/serializers.rb test/serializers_test.rb
git commit -m "Add serializer for snake_case to camelCase API translation"
```

---

### Task 5: Experiment Model

**Files:**
- Create: `lib/models/experiment.rb`
- Create: `test/models/experiment_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/experiment_test.rb
require_relative '../test_helper'

class ExperimentTest < Minitest::Test
  include TestHelper

  def setup
    seed_experiments
  end

  def test_list_of_genome
    genomes = ChipAtlas::Experiment.list_of_genome
    assert_includes genomes.keys, 'hg38'
    assert_includes genomes.keys, 'mm10'
    assert_equal 'H. sapiens (hg38)', genomes['hg38']
  end

  def test_list_of_experiment_types
    types = ChipAtlas::Experiment.list_of_experiment_types
    assert types.any? { |t| t[:id] == 'Histone' }
    assert types.any? { |t| t[:id] == 'CUT&Tag' }
    assert types.any? { |t| t[:id] == 'CUT&RUN' }
  end

  def test_experiment_types_with_counts
    result = ChipAtlas::Experiment.experiment_types('hg38', 'All cell types')
    histone = result.find { |r| r[:id] == 'Histone' }
    assert_equal 2, histone[:count]
  end

  def test_experiment_types_filtered_by_cell_class
    result = ChipAtlas::Experiment.experiment_types('hg38', 'Blood')
    histone = result.find { |r| r[:id] == 'Histone' }
    assert_equal 1, histone[:count]
  end

  def test_sample_types
    result = ChipAtlas::Experiment.sample_types('hg38', 'Histone')
    assert result.first[:id] == 'All cell types'
    assert result.first[:count] == 2
    blood = result.find { |r| r[:id] == 'Blood' }
    assert_equal 1, blood[:count]
  end

  def test_chip_antigen
    result = ChipAtlas::Experiment.chip_antigen('hg38', 'Histone', 'All cell types')
    assert result.first[:id] == '-'  # "All" entry
    h3k4 = result.find { |r| r[:id] == 'H3K4me3' }
    assert_equal 1, h3k4[:count]
  end

  def test_cell_type
    result = ChipAtlas::Experiment.cell_type('hg38', 'Histone', 'Blood')
    assert result.first[:id] == '-'  # "All" entry
    k562 = result.find { |r| r[:id] == 'K-562' }
    assert_equal 1, k562[:count]
  end

  def test_cell_type_returns_only_all_when_no_class
    result = ChipAtlas::Experiment.cell_type('hg38', 'Histone', 'All cell types')
    assert_equal 1, result.size
    assert_equal '-', result.first[:id]
  end

  def test_record_by_exp_id
    records = ChipAtlas::Experiment.record_by_exp_id('SRX018625')
    assert_equal 1, records.size
    assert_equal 'SRX018625', records.first[:expid]
    assert_equal 'Histone', records.first[:agClass]
  end

  def test_id_valid
    assert ChipAtlas::Experiment.id_valid?('SRX018625')
    refute ChipAtlas::Experiment.id_valid?('NONEXISTENT')
  end

  def test_number_of_experiments
    count = ChipAtlas::Experiment.number_of_experiments
    assert_equal 4, count
  end

  def test_total_number_of_reads
    total = ChipAtlas::Experiment.total_number_of_reads(['SRX018625', 'SRX018626'])
    assert_equal 35000000, total  # 15M + 20M
  end

  def test_index_all_genome
    index = ChipAtlas::Experiment.index_all_genome
    assert index.key?('hg38')
    assert index['hg38'].key?(:antigen)
    assert index['hg38'].key?(:celltype)
    assert index['hg38'][:antigen].key?('Histone')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/models/experiment_test.rb`
Expected: FAIL - `ChipAtlas::Experiment` not defined

- [ ] **Step 3: Write implementation**

```ruby
# lib/models/experiment.rb
module ChipAtlas
  module Experiment
    GENOMES = {
      'hg38'    => 'H. sapiens (hg38)',
      'mm10'    => 'M. musculus (mm10)',
      'rn6'     => 'R. norvegicus (rn6)',
      'dm6'     => 'D. melanogaster (dm6)',
      'ce11'    => 'C. elegans (ce11)',
      'sacCer3' => 'S. cerevisiae (sacCer3)',
      'TAIR10'  => 'A. thaliana (TAIR10)',
    }.freeze

    EXPERIMENT_TYPES = [
      { id: 'Histone',          label: 'ChIP: Histone' },
      { id: 'RNA polymerase',   label: 'ChIP: RNA polymerase' },
      { id: 'TFs and others',   label: 'ChIP: TFs and others' },
      { id: 'Input control',    label: 'ChIP: Input control' },
      { id: 'ATAC-Seq',         label: 'ATAC-Seq' },
      { id: 'DNase-seq',        label: 'DNase-seq' },
      { id: 'Bisulfite-Seq',    label: 'Bisulfite-Seq' },
      { id: 'CUT&Tag',          label: 'CUT&Tag' },
      { id: 'CUT&RUN',          label: 'CUT&RUN' },
      { id: 'Annotation tracks', label: 'Annotation tracks' },
    ].freeze

    module_function

    def dataset
      DB[:experiments]
    end

    def list_of_genome
      GENOMES
    end

    def list_of_experiment_types
      EXPERIMENT_TYPES
    end

    def experiment_types(genome, cl_class)
      subset = dataset.where(genome: genome)
      subset = subset.where(cl_class: cl_class) unless cl_class == 'All cell types'
      counts = subset.group_and_count(:ag_class).as_hash(:ag_class, :count)

      EXPERIMENT_TYPES.map do |t|
        { id: t[:id], label: t[:label], count: counts[t[:id]] }
      end
    end

    def sample_types(genome, ag_class)
      ag_class = EXPERIMENT_TYPES.first[:id] if ag_class == 'undefined'
      subset = dataset.where(genome: genome, ag_class: ag_class)

      result = [{ id: 'All cell types', label: 'All cell types', count: subset.count }]
      subset.group_and_count(:cl_class).each do |row|
        result << { id: row[:cl_class], label: row[:cl_class], count: row[:count] }
      end
      result
    end

    def chip_antigen(genome, ag_class, cl_class)
      ag_class = EXPERIMENT_TYPES.first[:id] if ag_class == 'undefined'
      result = [{ id: '-', label: 'All', count: nil }]

      subset = dataset.where(genome: genome, ag_class: ag_class)
      unless cl_class == 'undefined' || cl_class == 'All cell types'
        subset = subset.where(cl_class: cl_class)
      end

      subset.group_and_count(:ag_sub_class).each do |row|
        result << { id: row[:ag_sub_class], label: row[:ag_sub_class], count: row[:count] }
      end
      result
    end

    def cell_type(genome, ag_class, cl_class)
      result = [{ id: '-', label: 'All', count: nil }]

      if cl_class != 'undefined' && cl_class != 'All cell types'
        ag_class = EXPERIMENT_TYPES.first[:id] if ag_class == 'undefined'
        subset = dataset.where(genome: genome, ag_class: ag_class, cl_class: cl_class)
        subset.group_and_count(:cl_sub_class).each do |row|
          result << { id: row[:cl_sub_class], label: row[:cl_sub_class], count: row[:count] }
        end
      end
      result
    end

    def record_by_exp_id(exp_id)
      records = dataset.where(exp_id: exp_id).map do |row|
        ChipAtlas::Serializers.experiment(row)
      end
      records.sort_by { |r| -(r[:genome].match(/\d+/)[0].to_i rescue 0) }
    end

    def id_valid?(exp_id)
      dataset.where(exp_id: exp_id).count > 0
    end

    def number_of_experiments
      dataset.distinct.select(:exp_id).count
    end

    def total_number_of_reads(ids)
      dataset.where(exp_id: ids).sum do |row|
        row[:read_info].to_s.split(',')[0].to_i
      end
    end

    def index_all_genome
      result = {}
      GENOMES.each_key do |genome|
        result[genome] = index_by_genome(genome)
      end
      result
    end

    def index_by_genome(genome)
      index = { antigen: {}, celltype: {} }
      dataset.where(genome: genome).select(
        :ag_class, :ag_sub_class, :cl_class, :cl_sub_class
      ).each do |row|
        ag_cls = row[:ag_class]
        ag_sub = row[:ag_sub_class]
        cl_cls = row[:cl_class]
        cl_sub = row[:cl_sub_class]

        index[:antigen][ag_cls] ||= Hash.new(0)
        index[:antigen][ag_cls][ag_sub] += 1

        index[:celltype][cl_cls] ||= Hash.new(0)
        index[:celltype][cl_cls][cl_sub] += 1
      end
      index
    end

    def get_subclass(genome, ag_class, cl_class, subclass_type)
      ag_eval = ag_class == 'All antigens' && subclass_type == 'ag'
      cl_eval = cl_class == 'All cell types' && subclass_type == 'cl'
      return {} if ag_eval || cl_eval

      subset = dataset.where(genome: genome)
      subset = subset.where(ag_class: ag_class) unless ag_class == 'All antigens'
      subset = subset.where(cl_class: cl_class) unless cl_class == 'All cell types'

      col = subclass_type == 'ag' ? :ag_sub_class : :cl_sub_class
      counts = {}
      subset.select(col).each do |row|
        val = row[col]
        counts[val] ||= 0
        counts[val] += 1
      end
      counts
    end

    # Bulk load from TSV file
    def load_from_file(table_path)
      records = []
      timestamp = Time.now

      File.foreach(table_path, encoding: 'UTF-8') do |line_n|
        cols = line_n.chomp.split("\t")
        records << {
          exp_id:            cols[0],
          genome:            cols[1],
          ag_class:          cols[2],
          ag_sub_class:      cols[3],
          cl_class:          cols[4],
          cl_sub_class:      cols[5],
          cl_sub_class_info: cols[6],
          read_info:         cols[7],
          title:             cols[8],
          attributes:        cols[9..].to_a.join("\t"),
          created_at:        timestamp,
        }
      end

      dataset.multi_insert(records) if records.any?
      records.size
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby test/models/experiment_test.rb`
Expected: All tests pass

Note: `total_number_of_reads` iterates rows. If this becomes a bottleneck with real data, we can optimize with a SQL expression later. For now, correctness matches the original behavior.

- [ ] **Step 5: Commit**

```bash
git add lib/models/experiment.rb test/models/experiment_test.rb
git commit -m "Add Experiment model with Sequel, faceted queries, bulk load"
```

---

### Task 6: Bedfile, Bedsize, Analysis, Run Models

**Files:**
- Create: `lib/models/bedfile.rb`
- Create: `lib/models/bedsize.rb`
- Create: `lib/models/analysis.rb`
- Create: `lib/models/run.rb`
- Create: `test/models/bedfile_test.rb`

- [ ] **Step 1: Write the failing test for Bedfile**

```ruby
# test/models/bedfile_test.rb
require_relative '../test_helper'

class BedfileTest < Minitest::Test
  include TestHelper

  def setup
    seed_bedfiles
  end

  def test_get_filename
    condition = {
      'genome' => 'hg38', 'agClass' => 'Histone', 'agSubClass' => 'H3K4me3',
      'clClass' => 'Blood', 'clSubClass' => '-', 'qval' => '05'
    }
    filename = ChipAtlas::Bedfile.get_filename(condition)
    assert_equal 'H3K4me3.Blood.05', filename
  end

  def test_get_filename_raises_on_no_match
    condition = {
      'genome' => 'hg38', 'agClass' => 'Histone', 'agSubClass' => 'NONEXISTENT',
      'clClass' => 'Blood', 'clSubClass' => '-', 'qval' => '05'
    }
    assert_raises(ChipAtlas::Bedfile::NotFound) do
      ChipAtlas::Bedfile.get_filename(condition)
    end
  end

  def test_qval_range
    range = ChipAtlas::Bedfile.qval_range
    assert_includes range, '05'
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/models/bedfile_test.rb`
Expected: FAIL

- [ ] **Step 3: Write all four model implementations**

```ruby
# lib/models/bedfile.rb
module ChipAtlas
  module Bedfile
    NotFound = Class.new(StandardError)

    module_function

    def dataset
      DB[:bedfiles]
    end

    def get_filename(condition)
      results = filesearch(condition)
      raise NotFound, "No bedfile found for condition" if results.empty?
      raise NotFound, "Multiple bedfiles found" if results.size > 1
      results.first[:filename]
    end

    def get_trackname(condition)
      results = filesearch(condition)
      raise NotFound if results.size != 1
      results.first[:ag_sub_class]
    end

    def filesearch(condition)
      dataset
        .where(genome: condition['genome'])
        .where(ag_class: condition['agClass'])
        .where(ag_sub_class: condition['agSubClass'] || '-')
        .where(cl_class: condition['clClass'])
        .where(cl_sub_class: condition['clSubClass'] || '-')
        .where(qval: condition['qval'])
        .all
    end

    def qval_range
      dataset
        .exclude(ag_class: 'Bisulfite-Seq')
        .exclude(ag_class: 'Annotation tracks')
        .distinct
        .select_map(:qval)
        .sort
    end

    def load_from_file(table_path)
      records = []
      timestamp = Time.now

      File.foreach(table_path, encoding: 'UTF-8') do |line_n|
        cols = line_n.chomp.split("\t")
        records << {
          filename:     cols[0],
          genome:       cols[1],
          ag_class:     cols[2],
          ag_sub_class: cols[3],
          cl_class:     cols[4],
          cl_sub_class: cols[5],
          qval:         cols[6],
          experiments:  cols[7],
          created_at:   timestamp,
        }
      end

      dataset.multi_insert(records) if records.any?
      records.size
    end
  end
end
```

```ruby
# lib/models/bedsize.rb
module ChipAtlas
  module Bedsize
    module_function

    def dataset
      DB[:bedsizes]
    end

    def dump
      result = {}
      dataset.each do |row|
        key = [row[:genome], row[:ag_class], row[:cl_class], row[:qval]].join(',')
        result[key] = row[:number_of_lines]
      end
      result
    end

    def load_from_file(table_path)
      records = []
      timestamp = Time.now

      File.foreach(table_path, encoding: 'UTF-8') do |line_n|
        cols = line_n.chomp.split("\t")
        records << {
          genome:          cols[0],
          ag_class:        cols[1],
          cl_class:        cols[2],
          qval:            cols[3],
          number_of_lines: cols[4].to_i,
          created_at:      timestamp,
        }
      end

      dataset.multi_insert(records) if records.any?
      records.size
    end
  end
end
```

```ruby
# lib/models/analysis.rb
module ChipAtlas
  module Analysis
    module_function

    def dataset
      DB[:analyses]
    end

    def colo_result_by_genome(genome)
      result = { genome => { antigen: {}, cellline: {} } }

      dataset.where(genome: genome).each do |row|
        cell_list = row[:cell_list].to_s.split(',')
        next if cell_list.empty?

        antigen = row[:antigen]
        result[genome][:antigen][antigen] = cell_list

        cell_list.each do |cl|
          result[genome][:cellline][cl] ||= []
          result[genome][:cellline][cl] << antigen
        end
      end
      result
    end

    def target_genes_result
      result = {}
      dataset.where(target_genes: true).each do |row|
        genome = row[:genome]
        result[genome] ||= []
        result[genome] << row[:antigen]
      end
      result
    end

    def load_from_file(table_path)
      records = []
      timestamp = Time.now

      File.foreach(table_path, encoding: 'UTF-8') do |line_n|
        cols = line_n.chomp.split("\t")
        records << {
          antigen:      cols[0],
          cell_list:    cols[1],
          target_genes: cols[2] == '+',
          genome:       cols[3],
          created_at:   timestamp,
        }
      end

      dataset.multi_insert(records) if records.any?
      records.size
    end
  end
end
```

```ruby
# lib/models/run.rb
module ChipAtlas
  module Run
    module_function

    def dataset
      DB[:runs]
    end

    def exp2run(exp_id)
      dataset.where(exp_id: exp_id).select_map(:run_id)
    end

    def load_from_file(table_path)
      existing_exp_ids = DB[:experiments].distinct.select_map(:exp_id).to_set
      puts "   Found #{existing_exp_ids.size} experiment IDs for filtering"

      records = []
      timestamp = Time.now
      filtered_count = 0
      total_processed = 0
      batch_size = 50_000

      IO.popen("awk -F '\t' '$8 == \"live\" { print $1 \"\\t\" $3 }' #{table_path}") do |pipe|
        pipe.each_line do |line|
          total_processed += 1

          if total_processed % 100_000 == 0
            puts "   Processed #{total_processed} lines (#{filtered_count} matched)"
          end

          cols = line.chomp.split("\t")
          next if cols.size < 2

          run_id, exp_id = cols[0], cols[1]

          if existing_exp_ids.include?(exp_id)
            records << { run_id: run_id, exp_id: exp_id, created_at: timestamp }
            filtered_count += 1

            if records.size >= batch_size
              puts "   Inserting batch of #{records.size} records..."
              dataset.multi_insert(records)
              records.clear
            end
          end
        end
      end

      dataset.multi_insert(records) if records.any?
      puts "   Summary: #{filtered_count} runs from #{total_processed} total"
      filtered_count
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby test/models/bedfile_test.rb`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/models/bedfile.rb lib/models/bedsize.rb lib/models/analysis.rb lib/models/run.rb test/models/bedfile_test.rb
git commit -m "Add Bedfile, Bedsize, Analysis, Run models with Sequel"
```

---

### Task 7: ExperimentSearch (FTS5) and SraCache Models

**Files:**
- Create: `lib/models/experiment_search.rb`
- Create: `lib/models/sra_cache.rb`
- Create: `test/models/experiment_search_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/experiment_search_test.rb
require_relative '../test_helper'

class ExperimentSearchTest < Minitest::Test
  include TestHelper

  def setup
    # Insert into FTS5 table
    DB.run <<-SQL
      INSERT INTO experiments_fts (exp_id, sra_id, geo_id, genome, ag_class, ag_sub_class, cl_class, cl_sub_class, title, attributes)
      VALUES ('SRX018625', 'SRA123', 'GSM456', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K-562', 'H3K4me3 ChIP-seq in K-562 cells', 'leukemia cell line');
    SQL
    DB.run <<-SQL
      INSERT INTO experiments_fts (exp_id, sra_id, geo_id, genome, ag_class, ag_sub_class, cl_class, cl_sub_class, title, attributes)
      VALUES ('SRX018626', 'SRA124', 'GSM457', 'hg38', 'TFs and others', 'CTCF', 'Blood', 'K-562', 'CTCF ChIP-seq in K-562', 'cell line');
    SQL
    DB.run <<-SQL
      INSERT INTO experiments_fts (exp_id, sra_id, geo_id, genome, ag_class, ag_sub_class, cl_class, cl_sub_class, title, attributes)
      VALUES ('SRX100002', 'SRA200', 'GSM500', 'mm10', 'ATAC-Seq', '-', 'Liver', 'Hepatocyte', 'ATAC-seq mouse liver', 'primary cell');
    SQL
  end

  def test_search_by_keyword
    result = ChipAtlas::ExperimentSearch.search('K-562')
    assert_equal 2, result[:total]
    assert result[:experiments].all? { |e| e[:expid] }
  end

  def test_search_with_genome_filter
    result = ChipAtlas::ExperimentSearch.search('ATAC', genome: 'mm10')
    assert_equal 1, result[:total]
    assert_equal 'SRX100002', result[:experiments].first[:expid]
  end

  def test_search_with_limit
    result = ChipAtlas::ExperimentSearch.search('K-562', limit: 1)
    assert_equal 2, result[:total]
    assert_equal 1, result[:returned]
  end

  def test_search_empty_query
    result = ChipAtlas::ExperimentSearch.search('')
    assert_equal 0, result[:total]
  end

  def test_search_nil_query
    result = ChipAtlas::ExperimentSearch.search(nil)
    assert_equal 0, result[:total]
  end

  def test_search_with_offset
    result = ChipAtlas::ExperimentSearch.search('K-562', limit: 1, offset: 1)
    assert_equal 2, result[:total]
    assert_equal 1, result[:returned]
  end

  def test_sanitizes_special_characters
    # Should not raise even with FTS5 special chars
    result = ChipAtlas::ExperimentSearch.search('"CTCF" AND (test)')
    assert result.key?(:total)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/models/experiment_search_test.rb`
Expected: FAIL

- [ ] **Step 3: Write implementations**

```ruby
# lib/models/experiment_search.rb
module ChipAtlas
  module ExperimentSearch
    COLUMNS = %w[exp_id sra_id geo_id genome ag_class ag_sub_class
                 cl_class cl_sub_class title attributes].freeze

    module_function

    def search(query, genome: nil, limit: 20, offset: 0)
      return { total: 0, returned: 0, experiments: [] } if query.nil? || query.strip.empty?

      sanitized = fts5_sanitize(query)
      return { total: 0, returned: 0, experiments: [] } if sanitized.empty?

      where_clause = "experiments_fts MATCH '#{sanitized.gsub("'", "''")}'"
      if genome && !genome.empty?
        where_clause += " AND genome = '#{genome.gsub("'", "''")}'"
      end

      total = DB["SELECT COUNT(*) AS c FROM experiments_fts WHERE #{where_clause}"]
                .first[:c]

      rows = DB[<<-SQL].all
        SELECT #{COLUMNS.join(', ')}, rank
        FROM experiments_fts
        WHERE #{where_clause}
        ORDER BY rank
        LIMIT #{limit.to_i}
        OFFSET #{offset.to_i}
      SQL

      experiments = rows.map { |row| ChipAtlas::Serializers.search_result(row) }

      { total: total, returned: experiments.size, experiments: experiments }
    end

    def load_from_json(json_data)
      rows = json_data['data']
      return if rows.nil? || rows.empty?

      DB.run("DELETE FROM experiments_fts")

      rows.each_slice(500) do |batch|
        values_sql = batch.map do |row|
          vals = COLUMNS.each_with_index.map do |_, i|
            v = row[i]
            v = v.join(', ') if v.is_a?(Array)
            "'" + (v || '').to_s.gsub("'", "''") + "'"
          end
          "(#{vals.join(', ')})"
        end.join(', ')

        DB.run("INSERT INTO experiments_fts (#{COLUMNS.join(', ')}) VALUES #{values_sql}")
      end

      puts "ExperimentSearch: loaded #{rows.size} rows into FTS5 table"
    end

    def fts5_sanitize(query)
      tokens = query.strip.split(/\s+/).map do |token|
        cleaned = token.gsub(/["'()*^{}:]/, '')
        next nil if cleaned.empty?
        "\"#{cleaned}\""
      end.compact
      tokens.join(' ')
    end

    private_class_method :fts5_sanitize
  end
end
```

```ruby
# lib/models/sra_cache.rb
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
      if dataset.where(exp_id: exp_id).count > 0
        dataset.where(exp_id: exp_id).update(
          metadata_json: json, fetched_at: Time.now
        )
      else
        dataset.insert(
          exp_id: exp_id, metadata_json: json,
          fetched_at: Time.now, created_at: Time.now
        )
      end
    end

    def clear_expired
      cutoff = Time.now - TTL_SECONDS
      dataset.where { fetched_at < cutoff }.delete
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby test/models/experiment_search_test.rb`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/models/experiment_search.rb lib/models/sra_cache.rb test/models/experiment_search_test.rb
git commit -m "Add ExperimentSearch (FTS5) and SraCache models"
```

---

### Task 8: LocationService and WabiService

**Files:**
- Create: `lib/services/location_service.rb`
- Create: `lib/services/wabi_service.rb`
- Create: `lib/services/sra_service.rb`
- Create: `test/services/location_service_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/location_service_test.rb
require_relative '../test_helper'

class LocationServiceTest < Minitest::Test
  include TestHelper

  def setup
    seed_bedfiles
  end

  def test_archive_url
    data = { 'condition' => {
      'genome' => 'hg38', 'agClass' => 'Histone', 'agSubClass' => 'H3K4me3',
      'clClass' => 'Blood', 'clSubClass' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    url = svc.archive_url

    assert_match %r{https://chip-atlas\.dbcls\.jp/data/hg38/assembled/H3K4me3\.Blood\.05\.bed}, url
  end

  def test_igv_browsing_url
    data = { 'condition' => {
      'genome' => 'hg38', 'agClass' => 'Histone', 'agSubClass' => 'H3K4me3',
      'clClass' => 'Blood', 'clSubClass' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    url = svc.igv_browsing_url

    assert_match %r{http://localhost:60151/load\?genome=hg38}, url
  end

  def test_colo_url
    data = { 'condition' => {
      'genome' => 'hg38', 'antigen' => 'CTCF', 'cellline' => 'K-562'
    }}
    svc = ChipAtlas::LocationService.new(data)

    assert_match %r{/hg38/colo/CTCF\.K-562\.html}, svc.colo_url('submit')
    assert_match %r{/hg38/colo/CTCF\.K-562\.tsv}, svc.colo_url('tsv')
  end

  def test_target_genes_url
    data = { 'condition' => {
      'genome' => 'hg38', 'antigen' => 'CTCF', 'distance' => '5000'
    }}
    svc = ChipAtlas::LocationService.new(data)

    assert_match %r{/hg38/target/CTCF\.5000\.html}, svc.target_genes_url('submit')
    assert_match %r{/hg38/target/CTCF\.5000\.tsv}, svc.target_genes_url('tsv')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/services/location_service_test.rb`
Expected: FAIL

- [ ] **Step 3: Write implementations**

```ruby
# lib/services/location_service.rb
module ChipAtlas
  class LocationService
    ARCHIVE_BASE = 'https://chip-atlas.dbcls.jp/data/'.freeze

    def initialize(data)
      @data      = data
      @condition = data['condition']
      @genome    = @condition['genome']
    end

    def archive_url
      case @condition['agClass']
      when 'Annotation tracks' then annotation_url
      else bed_url
      end
    end

    def igv_browsing_url
      igv = @data['igv'] || 'http://localhost:60151'
      case @condition['agClass']
      when 'Annotation tracks'
        trackname = ChipAtlas::Bedfile.get_trackname(@condition).gsub(', ', '_')
        "#{igv}/load?genome=#{@genome}&file=#{annotation_url}&name=#{trackname}"
      else
        "#{igv}/load?genome=#{@genome}&file=#{bed_url}"
      end
    end

    def colo_url(type)
      antigen  = @condition['antigen']
      cellline = @condition['cellline'].gsub(' ', '_')
      base     = File.join(ARCHIVE_BASE, @genome, 'colo')
      case type
      when 'submit' then "#{base}/#{antigen}.#{cellline}.html"
      when 'tsv'    then "#{base}/#{antigen}.#{cellline}.tsv"
      when 'gml'    then "#{base}/#{cellline}.gml"
      end
    end

    def target_genes_url(type)
      antigen  = @condition['antigen']
      distance = @condition['distance']
      base     = File.join(ARCHIVE_BASE, @genome, 'target')
      ext = type == 'submit' ? 'html' : 'tsv'
      "#{base}/#{antigen}.#{distance}.#{ext}"
    end

    private

    def bed_url
      filename = ChipAtlas::Bedfile.get_filename(@condition)
      File.join(ARCHIVE_BASE, @genome, 'assembled', filename + '.bed')
    rescue ChipAtlas::Bedfile::NotFound
      nil
    end

    def annotation_url
      condition_with_all = @condition.merge('clClass' => 'All cell types')
      filename = ChipAtlas::Bedfile.get_filename(condition_with_all)
      File.join(ARCHIVE_BASE, 'annotations', @genome, filename)
    rescue ChipAtlas::Bedfile::NotFound
      nil
    end
  end
end
```

```ruby
# lib/services/wabi_service.rb
require 'net/http'
require 'uri'
require 'timeout'
require 'json'

module ChipAtlas
  module WabiService
    ENDPOINT = 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/'.freeze

    module_function

    def endpoint_available?
      Timeout.timeout(3) do
        URI.open(ENDPOINT).read == 'chipatlas'
      end
    rescue
      false
    end

    def submit_job(params)
      response = Net::HTTP.post_form(URI.parse(ENDPOINT), params)
      body = response.body
      return nil unless body

      id = body.split("\n").find { |l| l =~ /^requestId/ }&.split(/\s/)&.last
      id
    end

    def job_finished?(request_id)
      server_url = 'https://dtn1.ddbj.nig.ac.jp'
      endpoint = "/wabi/chipatlas/#{request_id}?info=result&format=html"

      uri = URI.parse(server_url + endpoint)
      response = Net::HTTP.get_response(uri)
      response.code == '200'
    rescue
      nil  # server unavailable
    end

    def fetch_log(request_id)
      uri = URI.parse("#{ENDPOINT}#{request_id}?info=result&format=log")
      URI.open(uri).read
    rescue
      nil
    end
  end
end
```

```ruby
# lib/services/sra_service.rb
require 'open-uri'
require 'nokogiri'
require 'json'

module ChipAtlas
  class SraService
    EUTILS_BASE = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils'.freeze

    def initialize(exp_id)
      @exp_id = exp_id
    end

    def fetch
      # Try cache first
      cached = ChipAtlas::SraCache.get(@exp_id)
      return cached if cached

      # Fetch from NCBI
      metadata = fetch_from_ncbi
      ChipAtlas::SraCache.set(@exp_id, metadata) if metadata
      metadata
    end

    private

    def fetch_from_ncbi
      uid = get_uid
      return error_metadata unless uid

      xml = Nokogiri::XML(URI.open("#{EUTILS_BASE}/efetch.fcgi?db=sra&id=#{uid}"))
      parse_experiment(xml)
    rescue OpenURI::HTTPError, Timeout::Error, StandardError
      error_metadata
    end

    def get_uid
      url = "#{EUTILS_BASE}/esearch.fcgi?db=sra&term=#{@exp_id}&retmode=json"
      result = JSON.parse(URI.open(url).read)
      ids = result.dig('esearchresult', 'idlist')
      ids&.size == 1 ? ids.first : nil
    rescue
      nil
    end

    def parse_experiment(xml)
      {
        exp_id: @exp_id,
        library_description: {
          library_name:                  xml.css('LIBRARY_NAME').inner_text,
          library_strategy:              xml.css('LIBRARY_STRATEGY').inner_text,
          library_source:                xml.css('LIBRARY_SOURCE').inner_text,
          library_selection:             xml.css('LIBRARY_SELECTION').inner_text,
          library_construction_protocol: xml.css('LIBRARY_CONSTRUCTION_PROTOCOL').inner_text,
        },
        platform_information: {
          instrument_model: xml.css('INSTRUMENT_MODEL').inner_text,
          cycle_sequence:   xml.css('CYCLE_SEQUENCE').inner_text,
          cycle_count:      xml.css('CYCLE_COUNT').inner_text,
          flow_sequence:    xml.css('FLOW_SEQUENCE').inner_text,
          flow_count:       xml.css('FLOW_COUNT').inner_text,
          key_sequence:     xml.css('KEY_SEQUENCE').inner_text,
        },
        platform:               (xml.css('PLATFORM').first&.children&.first&.name rescue nil),
        library_layout:         (xml.css('LIBRARY_LAYOUT').first&.children&.first&.name rescue nil),
        library_orientation:    (xml.css('LIBRARY_LAYOUT').first&.children&.first&.attr('ORIENTATION').to_s rescue ''),
        library_nominal_length: (xml.css('LIBRARY_LAYOUT').first&.children&.first&.attr('NOMINAL_LENGTH').to_s rescue ''),
        library_nominal_sdev:   (xml.css('LIBRARY_LAYOUT').first&.children&.first&.attr('NOMINAL_SDEV').to_s rescue ''),
      }
    end

    def error_metadata
      msg = 'ERROR: cannot retrieve data from NCBI'
      {
        exp_id: @exp_id,
        library_description: Hash.new(msg),
        platform_information: Hash.new(msg),
        platform: msg,
        library_layout: msg,
      }
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby test/services/location_service_test.rb`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/services/location_service.rb lib/services/wabi_service.rb lib/services/sra_service.rb test/services/location_service_test.rb
git commit -m "Add LocationService, WabiService, SraService"
```

---

### Task 9: Module Loader

**Files:**
- Create: `lib/chip_atlas.rb`

- [ ] **Step 1: Write the module loader**

This replaces `lib/pj.rb`. Loads all models and services.

```ruby
# lib/chip_atlas.rb
require_relative 'serializers'
require_relative 'models/experiment'
require_relative 'models/experiment_search'
require_relative 'models/bedfile'
require_relative 'models/bedsize'
require_relative 'models/analysis'
require_relative 'models/run'
require_relative 'models/sra_cache'
require_relative 'services/location_service'
require_relative 'services/wabi_service'
require_relative 'services/sra_service'

module ChipAtlas
  VERSION = '2.0.0'.freeze
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/chip_atlas.rb
git commit -m "Add ChipAtlas module loader"
```

---

### Task 10: Route Modules

**Files:**
- Create: `routes/api.rb`
- Create: `routes/pages.rb`
- Create: `routes/wabi.rb`
- Create: `routes/health.rb`
- Create: `test/routes/api_test.rb`
- Create: `test/routes/health_test.rb`

- [ ] **Step 1: Write the failing API route test**

```ruby
# test/routes/api_test.rb
require_relative '../test_helper'

# Load the app after test_helper sets up DB
require_relative '../../app'

class ApiTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelper

  def app
    ChipAtlasApp
  end

  def setup
    seed_all
  end

  def test_list_of_genome
    get '/data/list_of_genome.json'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_includes data, 'hg38'
    assert_includes data, 'TAIR10'
  end

  def test_list_of_experiment_types
    get '/data/list_of_experiment_types.json'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert data.any? { |t| t['id'] == 'CUT&Tag' }
  end

  def test_experiment_types_with_counts
    get '/data/experiment_types', genome: 'hg38', clClass: 'All cell types'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    histone = data.find { |d| d['id'] == 'Histone' }
    assert_equal 2, histone['count']
  end

  def test_sample_types
    get '/data/sample_types', genome: 'hg38', agClass: 'Histone'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert data.first['id'] == 'All cell types'
  end

  def test_chip_antigen
    get '/data/chip_antigen', genome: 'hg38', agClass: 'Histone', clClass: 'All cell types'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert data.first['id'] == '-'
  end

  def test_cell_type
    get '/data/cell_type', genome: 'hg38', agClass: 'Histone', clClass: 'Blood'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    k562 = data.find { |d| d['id'] == 'K-562' }
    assert k562
  end

  def test_exp_metadata
    get '/data/exp_metadata.json', expid: 'SRX018625'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 1, data.size
    assert_equal 'SRX018625', data.first['expid']
    assert_equal 'Histone', data.first['agClass']
  end

  def test_qval_range
    get '/data/qval_range.json'
    assert last_response.ok?
  end

  def test_number_of_lines
    get '/data/number_of_lines.json'
    assert last_response.ok?
  end

  def test_search
    # Seed FTS data
    DB.run <<-SQL
      INSERT INTO experiments_fts (exp_id, sra_id, geo_id, genome, ag_class, ag_sub_class, cl_class, cl_sub_class, title, attributes)
      VALUES ('SRX018625', '', '', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K-562', 'H3K4me3 in K-562', '');
    SQL

    get '/data/search', q: 'K-562', genome: 'hg38', limit: '10'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert data['total'] >= 1
  end

  def test_post_download
    post '/download', JSON.generate({
      condition: { genome: 'hg38', agClass: 'Histone', agSubClass: 'H3K4me3',
                   clClass: 'Blood', clSubClass: '-', qval: '05' }
    }), 'CONTENT_TYPE' => 'application/json'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match(/chip-atlas\.dbcls\.jp/, data['url'])
  end

  def test_post_browse
    post '/browse', JSON.generate({
      condition: { genome: 'hg38', agClass: 'Histone', agSubClass: 'H3K4me3',
                   clClass: 'Blood', clSubClass: '-', qval: '05' }
    }), 'CONTENT_TYPE' => 'application/json'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match(/localhost:60151/, data['url'])
  end
end
```

- [ ] **Step 2: Write the health test**

```ruby
# test/routes/health_test.rb
require_relative '../test_helper'
require_relative '../../app'

class HealthTest < Minitest::Test
  include Rack::Test::Methods

  def app
    ChipAtlasApp
  end

  def test_health_returns_ok
    get '/health'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'ok', data['status']
    assert_equal 'ok', data['checks']['database']
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bundle exec ruby test/routes/api_test.rb`
Expected: FAIL - `ChipAtlasApp` not defined

- [ ] **Step 4: Write route modules**

```ruby
# routes/health.rb
module ChipAtlas
  module Routes
    module Health
      def self.registered(app)
        app.get '/health' do
          checks = {}

          begin
            DB.execute("SELECT 1")
            checks[:database] = 'ok'
          rescue => e
            checks[:database] = 'error'
            checks[:database_error] = e.message
          end

          config_loaded = settings.respond_to?(:list_of_genome) && settings.list_of_genome
          checks[:config] = config_loaded ? 'ok' : 'not_loaded'

          healthy = checks[:database] == 'ok'
          status healthy ? 200 : 503
          content_type 'application/json'
          JSON.generate({ status: healthy ? 'ok' : 'error', checks: checks })
        end
      end
    end
  end
end
```

```ruby
# routes/api.rb
module ChipAtlas
  module Routes
    module Api
      def self.registered(app)
        app.get '/data/:data.json' do
          data = case params[:data]
                 when 'index_all_genome'          then settings.index_all_genome
                 when 'list_of_genome'            then settings.list_of_genome.keys
                 when 'list_of_experiment_types'  then settings.list_of_experiment_types
                 when 'qval_range'                then settings.qval_range
                 when 'exp_metadata'              then ChipAtlas::Experiment.record_by_exp_id(params[:expid])
                 when 'colo_analysis'             then ChipAtlas::Analysis.colo_result_by_genome(params[:genome])
                 when 'target_genes_analysis'     then settings.target_genes_analysis
                 when 'number_of_lines'           then settings.bedsizes
                 when 'index_subclass'
                   ChipAtlas::Experiment.get_subclass(
                     params[:genome], params[:agClass], params[:clClass], params[:type]
                   )
                 when 'ExperimentList'            then settings.experiment_list
                 when 'ExperimentList_adv'        then settings.experiment_list_adv
                 end
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/experiment_types' do
          data = ChipAtlas::Experiment.experiment_types(params[:genome], params[:clClass])
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/sample_types' do
          data = ChipAtlas::Experiment.sample_types(params[:genome], params[:agClass])
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/chip_antigen' do
          data = ChipAtlas::Experiment.chip_antigen(params[:genome], params[:agClass], params[:clClass])
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/cell_type' do
          data = ChipAtlas::Experiment.cell_type(params[:genome], params[:agClass], params[:clClass])
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/search' do
          query  = params[:q]
          genome = params[:genome]
          limit  = (params[:limit] || 20).to_i.clamp(1, 100)
          offset = (params[:offset] || 0).to_i
          data = ChipAtlas::ExperimentSearch.search(query, genome: genome, limit: limit, offset: offset)
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/qvalue_range' do
          content_type 'application/json'
          JSON.generate(settings.qval_range)
        end

        app.post '/browse' do
          request.body.rewind
          json = JSON.parse(request.body.read)
          url = ChipAtlas::LocationService.new(json).igv_browsing_url
          content_type 'application/json'
          JSON.generate({ 'url' => url })
        end

        app.post '/download' do
          request.body.rewind
          json = JSON.parse(request.body.read)
          url = ChipAtlas::LocationService.new(json).archive_url
          content_type 'application/json'
          JSON.generate({ 'url' => url })
        end

        app.post '/colo' do
          request.body.rewind
          json = JSON.parse(request.body.read)
          url = ChipAtlas::LocationService.new(json).colo_url(params[:type])
          content_type 'application/json'
          JSON.generate({ 'url' => url })
        end

        app.post '/target_genes' do
          request.body.rewind
          json = JSON.parse(request.body.read)
          url = ChipAtlas::LocationService.new(json).target_genes_url(params[:type])
          content_type 'application/json'
          JSON.generate({ 'url' => url })
        end

        app.post '/diff_analysis_estimated_time' do
          request.body.rewind
          data = JSON.parse(request.body.read)
          total_reads = ChipAtlas::Experiment.total_number_of_reads(data['ids']).to_i
          seconds = case data['analysis']
                    when 'dmr'      then 117.13 * Math.log(total_reads) - 2012.5 + 600
                    when 'diffbind' then 1.80e-6 * total_reads + 119.38 + 600
                    end
          minutes = (seconds && !seconds.infinite?) ? Rational(seconds, 60).to_f.round : nil
          content_type 'application/json'
          JSON.generate({ minutes: minutes })
        end

        app.get '/api/remoteUrlStatus' do
          Net::HTTP.get_response(URI.parse(params[:url])).code.to_i.to_s
        end
      end
    end
  end
end
```

```ruby
# routes/wabi.rb
require 'net/http'

module ChipAtlas
  module Routes
    module Wabi
      def self.registered(app)
        app.get '/wabi_endpoint_status' do
          ChipAtlas::WabiService.endpoint_available? ? 'chipatlas' : ''
        end

        app.get '/wabi_chipatlas' do
          result = ChipAtlas::WabiService.job_finished?(params[:id])
          case result
          when true  then 'finished'
          when false then 'running'
          else 'server unavailable'
          end
        end

        app.post '/wabi_chipatlas' do
          unless ChipAtlas::WabiService.endpoint_available?
            halt 503
          end

          post_data = if request.content_type&.include?('application/json')
            request.body.rewind
            JSON.parse(request.body.read)
          else
            params
          end

          request_id = ChipAtlas::WabiService.submit_job(post_data)
          if request_id
            content_type 'application/json'
            JSON.generate({ 'requestId' => request_id })
          else
            content_type 'application/json'
            JSON.generate({ 'request_body' => post_data.to_s })
          end
        end

        app.get '/enrichment_analysis_log' do
          log = ChipAtlas::WabiService.fetch_log(params[:id])
          if log
            log
          else
            status 404
            'Log file not available yet'
          end
        end

        app.get '/diff_analysis_log' do
          log = ChipAtlas::WabiService.fetch_log(params[:id])
          if log
            log
          else
            status 404
            'Log file not available yet'
          end
        end
      end
    end
  end
end
```

```ruby
# routes/pages.rb
module ChipAtlas
  module Routes
    module Pages
      def self.registered(app)
        app.get '/' do
          @number_of_experiments = settings.number_of_experiments
          erb :about
        end

        app.get '/peak_browser' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome   = settings.list_of_genome
          @qval_range       = settings.qval_range
          erb :peak_browser
        end

        app.get '/view' do
          @expid = params[:id].upcase
          if @expid =~ /^GSM/
            redirect "/view?id=#{settings.gsm_to_srx[@expid]}"
          end
          redirect 'not_found', 404 unless ChipAtlas::Experiment.id_valid?(@expid)
          @ncbi = ChipAtlas::SraService.new(@expid).fetch
          erb :experiment
        end

        app.get '/colo' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome = settings.list_of_genome
          erb :colo
        end

        app.get '/colo_result' do
          url = params[:base]
          begin
            response = Net::HTTP.get_response(URI.parse(url))
            response.code == '200' ? redirect(url) : (redirect 'not_found', 404)
          rescue
            redirect 'not_found', 404
          end
        end

        app.get '/target_genes' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome = settings.list_of_genome
          erb :target_genes
        end

        app.get '/target_genes_result' do
          url = params[:base]
          begin
            response = Net::HTTP.get_response(URI.parse(url))
            response.code == '200' ? redirect(url) : (redirect 'not_found', 404)
          rescue
            redirect 'not_found', 404
          end
        end

        app.get '/enrichment_analysis' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome   = settings.list_of_genome
          @qval_range       = settings.qval_range
          erb :enrichment_analysis
        end

        app.post '/enrichment_analysis' do
          request.body.rewind
          raw = request.body.read
          pairs = raw.split('&').map { |kv| kv.split('=') }
          form = Hash[pairs]
          @taxonomy  = form['taxonomy']
          @genes     = form['genes']
          @genesetA  = form['genesetA']
          @genesetB  = form['genesetB']
          @index_all_genome = settings.index_all_genome
          @list_of_genome   = settings.list_of_genome
          @qval_range       = settings.qval_range
          erb :enrichment_analysis
        end

        app.get '/enrichment_analysis_result' do
          erb :enrichment_analysis_result
        end

        app.get '/diff_analysis' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome   = settings.list_of_genome
          @qval_range       = settings.qval_range
          erb :diff_analysis
        end

        app.get '/diff_analysis_result' do
          erb :diff_analysis_result
        end

        app.get '/search' do
          erb :search
        end

        app.get '/publications' do
          erb :publications
        end

        app.get '/agents' do
          erb :agents
        end

        app.get '/demo' do
          erb :demo
        end

        app.not_found do
          erb :not_found
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby test/routes/api_test.rb && bundle exec ruby test/routes/health_test.rb`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add routes/ test/routes/
git commit -m "Add route modules: API, pages, WABI proxy, health check"
```

---

### Task 11: Main App Entry Point

**Files:**
- Modify: `app.rb`
- Modify: `config.ru`
- Modify: `Rakefile`

- [ ] **Step 1: Write new app.rb**

The new entry point is slim - just configuration and registration of route modules.

```ruby
# app.rb
# :)

$LOAD_PATH << __dir__
$LOAD_PATH << File.join(__dir__, 'lib')

require 'bundler'
Bundler.require
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'sequel'
require 'sinatra/base'

ENV['DATABASE_URL'] ||= "sqlite://database.sqlite"
DB = Sequel.connect(ENV['DATABASE_URL'], pool_timeout: 300)
DB.run("PRAGMA journal_mode=WAL") rescue nil

require 'lib/chip_atlas'
require 'routes/health'
require 'routes/api'
require 'routes/pages'
require 'routes/wabi'

class ChipAtlasApp < Sinatra::Base
  set :erb, escape_html: true

  register ChipAtlas::Routes::Health
  register ChipAtlas::Routes::Api
  register ChipAtlas::Routes::Wabi
  register ChipAtlas::Routes::Pages

  helpers do
    def app_root
      "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}#{env['SCRIPT_NAME']}"
    end
  end

  private

  def self.download_json_with_fallback(remote_url, local_filename)
    local_path = File.join('public', local_filename)

    if File.exist?(local_path)
      puts "Using cached file: #{local_path}"
      return JSON.parse(File.read(local_path))
    end

    begin
      puts "No cached file found, downloading from remote: #{remote_url}"
      Timeout.timeout(30) do
        content = URI.open(remote_url).read
        File.write(local_path, content)
        JSON.parse(content)
      end
    rescue => e
      puts "Failed to download #{remote_url}: #{e.message}"
      raise "Unable to load #{remote_url} and no cached file available"
    end
  end

  configure do
    set :wabi_endpoint, 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/'

    unless ENV['SKIP_APP_CONFIGURE']
      count = ChipAtlas::Experiment.number_of_experiments
      set :number_of_experiments, (count / 1000 * 1000).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      set :index_all_genome, ChipAtlas::Experiment.index_all_genome
      set :list_of_genome, ChipAtlas::Experiment.list_of_genome
      set :list_of_experiment_types, ChipAtlas::Experiment.list_of_experiment_types
      set :qval_range, ChipAtlas::Bedfile.qval_range
      set :target_genes_analysis, ChipAtlas::Analysis.target_genes_result
      set :bedsizes, ChipAtlas::Bedsize.dump

      set :experiment_list, download_json_with_fallback(
        'https://chip-atlas.dbcls.jp/data/metadata/ExperimentList.json', 'ExperimentList.json'
      )
      set :experiment_list_adv, download_json_with_fallback(
        'https://chip-atlas.dbcls.jp/data/metadata/ExperimentList_adv.json', 'ExperimentList_adv.json'
      )
      ChipAtlas::ExperimentSearch.load_from_json(settings.experiment_list_adv)
      set :gsm_to_srx, Hash[settings.experiment_list['data'].map { |a| [a[2], a[0]] }]
    end
  end

  configure :production do
    set :host_authorization, { permitted_hosts: ['.chip-atlas.org'] }
  end

  before do
    rack_input = request.env['rack.input'].read
    unless rack_input.empty?
      posted_data = JSON.parse(rack_input) rescue nil
      if posted_data
        log = [Time.now, request.ip, request.path_info, posted_data].join("\t")
        logfile = './log/access_log'
        FileUtils.mkdir_p(File.dirname(logfile))
        File.open(logfile, 'a') { |f| f.puts(log) }
      end
    end
  end
end
```

- [ ] **Step 2: Write new config.ru**

```ruby
# config.ru
require File.dirname(__FILE__) + '/app'
use Rack::RewindableInput::Middleware
run ChipAtlasApp
```

- [ ] **Step 3: Write new Rakefile**

```ruby
# Rakefile
ENV['SKIP_APP_CONFIGURE'] = '1'

require 'sequel'
ENV['DATABASE_URL'] ||= "sqlite://database.sqlite"
DB = Sequel.connect(ENV['DATABASE_URL'])

$LOAD_PATH << __dir__
$LOAD_PATH << File.join(__dir__, 'lib')
require 'lib/chip_atlas'

require 'rake'

PROJ_ROOT = File.expand_path(__dir__)

# Sequel migrations
namespace :db do
  desc "Run database migrations"
  task :migrate do
    Sequel::Migrator.run(DB, File.join(PROJ_ROOT, 'db', 'migrations'))
    puts "Migrations complete"
  end

  desc "Reset database (drop all tables and re-migrate)"
  task :reset do
    DB.tables.each { |t| DB.drop_table(t) }
    DB.run("DROP TABLE IF EXISTS experiments_fts")
    Rake::Task['db:migrate'].invoke
    puts "Database reset complete"
  end
end

Dir["#{PROJ_ROOT}/lib/tasks/**/*.rake"].each { |path| load path }

namespace :pj do
  desc "Load metadata from files into database"
  task :load_metadata do
    Rake::Task['metadata:load'].invoke
  end
end
```

- [ ] **Step 4: Run all tests**

Run: `bundle exec ruby -e "Dir['test/**/*_test.rb'].each{|f| require_relative f}"`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add app.rb config.ru Rakefile
git commit -m "Wire up new app entry point with Sequel, route modules, WAL mode"
```

---

### Task 12: Metadata Rake Tasks (Sequel version)

**Files:**
- Create: `lib/tasks/metadata.rake`

- [ ] **Step 1: Write the Sequel-based metadata Rake tasks**

```ruby
# lib/tasks/metadata.rake
require 'open-uri'

namespace :metadata do
  datetime = Time.now.strftime('%Y%m%d-%H%M')
  metadata_dir = ENV['metadata_dir'] || File.join(PROJ_ROOT, 'metadata', datetime)
  directory metadata_dir

  experiment_table_fpath  = File.join(metadata_dir, 'experimentList.tab')
  bedfile_table_fpath     = File.join(metadata_dir, 'fileList.tab')
  analysis_table_fpath    = File.join(metadata_dir, 'analysisList.tab')
  bedsize_table_fpath     = File.join(metadata_dir, 'lineNum.tsv')
  run_members_table_fpath = File.join(metadata_dir, 'SRA_Run_Members.tab')

  metadata_base = 'https://chip-atlas.dbcls.jp/data/metadata'
  util_base     = 'https://chip-atlas.dbcls.jp/data/util'

  file experiment_table_fpath => metadata_dir do |t|
    puts 'Downloading experiments metadata...'
    start = Time.now
    File.write(t.name, URI.open("#{metadata_base}/experimentList.tab").read)
    puts "   Downloaded experimentList.tab (#{sprintf('%.2f', Time.now - start)}s)"
  end

  file bedfile_table_fpath => metadata_dir do |t|
    puts 'Downloading bedfiles metadata...'
    start = Time.now
    File.write(t.name, URI.open("#{metadata_base}/fileList.tab").read)
    puts "   Downloaded fileList.tab (#{sprintf('%.2f', Time.now - start)}s)"
  end

  file analysis_table_fpath => metadata_dir do |t|
    puts 'Downloading analysis metadata...'
    start = Time.now
    File.write(t.name, URI.open("#{metadata_base}/analysisList.tab").read)
    puts "   Downloaded analysisList.tab (#{sprintf('%.2f', Time.now - start)}s)"
  end

  file bedsize_table_fpath => metadata_dir do |t|
    puts 'Downloading bedsize metadata...'
    start = Time.now
    File.write(t.name, URI.open("#{util_base}/lineNum.tsv").read)
    puts "   Downloaded lineNum.tsv (#{sprintf('%.2f', Time.now - start)}s)"
  end

  file run_members_table_fpath => metadata_dir do |t|
    puts 'Downloading SRA run members metadata...'
    start = Time.now
    base  = 'ftp.ncbi.nlm.nih.gov/sra/reports/Metadata'
    fname = 'SRA_Run_Members.tab'
    `lftp -c "open #{base} && pget -n 8 -O #{File.dirname(t.name)} #{fname}"`
    puts "   Downloaded SRA_Run_Members.tab (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load => [:load_experiment, :load_bedfile, :load_analysis, :load_bedsize, :load_run, :load_fts] do
    puts 'All metadata loading completed successfully!'
  end

  task :load_experiment => experiment_table_fpath do
    puts '[1/6] Loading experiments data...'
    start = Time.now
    DB[:experiments].delete
    count = ChipAtlas::Experiment.load_from_file(experiment_table_fpath)
    puts "   #{count} experiments loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_bedfile => bedfile_table_fpath do
    puts '[2/6] Loading bedfiles data...'
    start = Time.now
    DB[:bedfiles].delete
    count = ChipAtlas::Bedfile.load_from_file(bedfile_table_fpath)
    puts "   #{count} bedfiles loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_analysis => analysis_table_fpath do
    puts '[3/6] Loading analysis data...'
    start = Time.now
    DB[:analyses].delete
    count = ChipAtlas::Analysis.load_from_file(analysis_table_fpath)
    puts "   #{count} analyses loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_bedsize => bedsize_table_fpath do
    puts '[4/6] Loading bedsize data...'
    start = Time.now
    DB[:bedsizes].delete
    count = ChipAtlas::Bedsize.load_from_file(bedsize_table_fpath)
    puts "   #{count} bedsizes loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_run => run_members_table_fpath do
    puts '[5/6] Loading runs data...'
    exp_count = DB[:experiments].count
    if exp_count == 0
      puts '   ERROR: No experiments found. Run metadata:load_experiment first.'
      exit 1
    end
    start = Time.now
    DB[:runs].delete
    count = ChipAtlas::Run.load_from_file(run_members_table_fpath)
    puts "   #{count} runs loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_fts do
    puts '[6/6] Loading FTS5 search index...'
    start = Time.now
    json_path = File.join(PROJ_ROOT, 'public', 'ExperimentList_adv.json')
    if File.exist?(json_path)
      json_data = JSON.parse(File.read(json_path))
      ChipAtlas::ExperimentSearch.load_from_json(json_data)
      puts "   FTS5 index loaded (#{sprintf('%.2f', Time.now - start)}s)"
    else
      puts '   Skipping FTS5: ExperimentList_adv.json not found'
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/tasks/metadata.rake
git commit -m "Port metadata Rake tasks to Sequel"
```

---

### Task 13: Run Full Test Suite and Verify

**Files:** None new - this is a verification task.

- [ ] **Step 1: Run all unit tests**

Run: `bundle exec ruby -e "Dir['test/**/*_test.rb'].each{|f| require_relative f}"`
Expected: All tests pass with 0 failures

- [ ] **Step 2: Create and migrate the database**

Run: `bundle exec rake db:migrate`
Expected: `Migrations complete`

- [ ] **Step 3: Boot the app (without data)**

Run: `SKIP_APP_CONFIGURE=1 bundle exec rackup -p 9293 &`
Then: `curl -s http://localhost:9293/health | python3 -m json.tool`
Expected: `{"status": "ok", "checks": {"database": "ok", "config": "not_loaded"}}`
Then: kill the background process

- [ ] **Step 4: Commit any fixes needed**

```bash
git add -A
git commit -m "Fix any issues found during integration testing"
```

- [ ] **Step 5: Final commit for backend foundation**

```bash
git log --oneline sengu..HEAD
```

Expected: ~12 clean commits building up the backend from dependencies to working routes.

---

## Summary

This plan produces a working Sinatra backend with:
- **Sequel ORM** with clean snake_case schema and composite indexes
- **6 models** (Experiment, Bedfile, Bedsize, Analysis, Run, SraCache) + ExperimentSearch (FTS5)
- **3 services** (LocationService, WabiService, SraService with caching)
- **4 route modules** (API, Pages, WABI, Health) preserving all existing endpoints
- **Serialization layer** for snake_case → camelCase API responses
- **Test suite** with Minitest + Rack::Test + seed data helpers
- **Metadata Rake tasks** ported to Sequel

All existing API endpoints are preserved. The MCP server should work unchanged. Pages routes return stubs (ERB templates will be created in Plan 2/3).

Next plan: **Frontend Foundation** (esbuild, TypeScript API client, CSS design system, shared components).
