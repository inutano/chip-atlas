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
