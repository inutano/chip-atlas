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
      !dataset.where(exp_id: exp_id).empty?
    end

    def number_of_experiments
      dataset.distinct.select(:exp_id).count
    end

    def total_number_of_reads(ids)
      dataset.where(exp_id: ids).select_map(:read_info).sum do |info|
        info.to_s.split(',')[0].to_i
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

      # Antigen index via SQL GROUP BY
      dataset.where(genome: genome)
        .group_and_count(:ag_class, :ag_sub_class)
        .each do |row|
          ag_cls = row[:ag_class]
          ag_sub = row[:ag_sub_class]
          index[:antigen][ag_cls] ||= Hash.new(0)
          index[:antigen][ag_cls][ag_sub] = row[:count]
        end

      # Cell type index via SQL GROUP BY
      dataset.where(genome: genome)
        .group_and_count(:cl_class, :cl_sub_class)
        .each do |row|
          cl_cls = row[:cl_class]
          cl_sub = row[:cl_sub_class]
          index[:celltype][cl_cls] ||= Hash.new(0)
          index[:celltype][cl_cls][cl_sub] = row[:count]
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
      subset.group_and_count(col).as_hash(col, :count)
    end

    def load_from_file(table_path)
      records = []
      timestamp = Time.now
      total = 0
      batch_size = 5_000

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

        if records.size >= batch_size
          dataset.multi_insert(records)
          total += records.size
          records.clear
        end
      end

      if records.any?
        dataset.multi_insert(records)
        total += records.size
      end
      total
    end
  end
end
