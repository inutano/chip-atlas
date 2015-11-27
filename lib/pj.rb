require 'pj/metadata'
require 'pj/sra'
require 'pj/bedfile'
require 'pj/experiment'

module PJ
  class << self
    def archive_base
      "http://dbarchive.biosciencedbc.jp/kyushu-u/"
    end

    def fileformat
      ".bed"
    end
  end

  def initialize(expid)
    @expid = expid
  end

  def id_valid?
    !self.where(:expid => @expid).empty?
  end

  def record_by_expid
    records = PJ::Experiment.where(:expid => @expid)
    raise NameError if records.size > 1
    record = records.first
    {
      :expid      => @expid,
      :genome     => record.genome,
      :agClass    => record.agClass,
      :agSubClass => record.agSubClass,
      :clClass    => record.clClass,
      :clSubClass => record.clSubClass,
      :title      => record.title,
      :attributes => record.additional_attributes,
      :readInfo   => record.readInfo,
      :clSubClassInfo => record.clSubClassInfo,
     }
  end
end
