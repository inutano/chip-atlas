# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2015_11_28_015049) do
  create_table "analyses", force: :cascade do |t|
    t.string "antigen"
    t.string "cell_list"
    t.boolean "target_genes"
    t.string "genome"
    t.datetime "timestamp", precision: nil
    t.index ["antigen"], name: "index_analyses_on_antigen"
    t.index ["cell_list"], name: "index_analyses_on_cell_list"
    t.index ["genome"], name: "index_analyses_on_genome"
    t.index ["target_genes"], name: "index_analyses_on_target_genes"
  end

  create_table "bedfiles", force: :cascade do |t|
    t.string "filename"
    t.string "genome"
    t.string "agClass"
    t.string "agSubClass"
    t.string "clClass"
    t.string "clSubClass"
    t.string "qval"
    t.string "experiments"
    t.datetime "timestamp", precision: nil
    t.index ["agClass"], name: "index_bedfiles_on_agClass"
    t.index ["agSubClass"], name: "index_bedfiles_on_agSubClass"
    t.index ["clClass"], name: "index_bedfiles_on_clClass"
    t.index ["clSubClass"], name: "index_bedfiles_on_clSubClass"
    t.index ["genome"], name: "index_bedfiles_on_genome"
    t.index ["qval"], name: "index_bedfiles_on_qval"
  end

  create_table "bedsizes", force: :cascade do |t|
    t.string "genome"
    t.string "agClass"
    t.string "clClass"
    t.string "qval"
    t.integer "number_of_lines", limit: 8
    t.datetime "timestamp", precision: nil
    t.index ["agClass"], name: "index_bedsizes_on_agClass"
    t.index ["clClass"], name: "index_bedsizes_on_clClass"
    t.index ["genome"], name: "index_bedsizes_on_genome"
    t.index ["number_of_lines"], name: "index_bedsizes_on_number_of_lines"
    t.index ["qval"], name: "index_bedsizes_on_qval"
  end

  create_table "experiments", force: :cascade do |t|
    t.string "expid"
    t.string "genome"
    t.string "agClass"
    t.string "agSubClass"
    t.string "clClass"
    t.string "clSubClass"
    t.string "title"
    t.string "additional_attributes"
    t.datetime "timestamp", precision: nil
    t.string "clSubClassInfo"
    t.string "readInfo"
    t.index ["agClass"], name: "index_experiments_on_agClass"
    t.index ["agSubClass"], name: "index_experiments_on_agSubClass"
    t.index ["clClass"], name: "index_experiments_on_clClass"
    t.index ["clSubClass"], name: "index_experiments_on_clSubClass"
    t.index ["expid"], name: "index_experiments_on_expid"
  end

  create_table "runs", force: :cascade do |t|
    t.string "runid"
    t.string "expid"
    t.datetime "timestamp", precision: nil
    t.index ["expid"], name: "index_runs_on_expid"
    t.index ["runid"], name: "index_runs_on_runid"
  end

end
