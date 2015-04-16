# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20150415101316) do

  create_table "bedfiles", force: :cascade do |t|
    t.string "filename"
    t.string "genome"
    t.string "agClass"
    t.string "agSubClass"
    t.string "clClass"
    t.string "clSubClass"
    t.string "qval"
    t.string "experiments"
  end

  add_index "bedfiles", ["agClass"], name: "index_bedfiles_on_agClass"
  add_index "bedfiles", ["agSubClass"], name: "index_bedfiles_on_agSubClass"
  add_index "bedfiles", ["clClass"], name: "index_bedfiles_on_clClass"
  add_index "bedfiles", ["clSubClass"], name: "index_bedfiles_on_clSubClass"
  add_index "bedfiles", ["genome"], name: "index_bedfiles_on_genome"
  add_index "bedfiles", ["qval"], name: "index_bedfiles_on_qval"

  create_table "experiments", force: :cascade do |t|
    t.string "expid"
    t.string "genome"
    t.string "agClass"
    t.string "agSubClass"
    t.string "clClass"
    t.string "clSubClass"
    t.string "title"
    t.string "additional_attributes"
  end

  add_index "experiments", ["agClass"], name: "index_experiments_on_agClass"
  add_index "experiments", ["agSubClass"], name: "index_experiments_on_agSubClass"
  add_index "experiments", ["clClass"], name: "index_experiments_on_clClass"
  add_index "experiments", ["clSubClass"], name: "index_experiments_on_clSubClass"
  add_index "experiments", ["expid"], name: "index_experiments_on_expid"

end
