#
# Run with
#
#   ruby -I lib test/test_sparql.rb
#
# Requires a running SPARQL end point
#
require 'minitest'
require 'minitest/autorun'
require 'list'
require 'pp'

class TestSPARQL < MiniTest::Test

  AUTHORS =<<AUTHORQ
       prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>
       prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
       prefix dc: <http://purl.org/dc/terms/>
       prefix bhx: <http://biohackerxiv.org/resource/>
       prefix schema: <https://schema.org/>

       SELECT ?o (xsd:integer(REPLACE(str(?p),
           "http://www.w3.org/1999/02/22-rdf-syntax-ns#_", "")) as ?pos) ?p
          FROM    <https://BioHackrXiv.org/graph>
          WHERE   {
             # <https://biohackrxiv.org/km9ux> dc:contributor ?node .
             <https://biohackrxiv.org/wu9et> dc:contributor ?node .
             # ?url dc:contributor ?node .
             ?node ?p ?o .
          } order by ?pos
AUTHORQ

  include BHXIVUtils::PaperList

  def setup
    print("Loading events...\n")
    @@biohackathons = BHXIVUtils::PaperList.biohackathon_events
    print("Loading papers...\n")
    @@papers = Hash[@@biohackathons.keys.map{|bh| [bh, BHXIVUtils::PaperList.bh_papers_list(bh)] }]
    print("Done setting up\n")
  end

  def test_authors
    # paper = "https://biohackrxiv.org/wu9et"
    paper = "https://biohackrxiv.org/km9ux"
    print(BHXIVUtils::PaperList.author_query(paper))
    authors = BHXIVUtils::PaperList.sparql(BHXIVUtils::PaperList.author_query(paper),lambda{|author| author[:author] })
    assert_equal ["Chris Mungall", "Hirokazu Chiba", "Shuichi Kawashima", "Yasunori Yamamoto", "Pjotr Prins", "Nada Amin", "Deepak Unni", "<nobr>William&nbsp;E.&nbsp;Byrd</nobr>"],authors
  end

  def test_papers
    # pp papers
    papers = @@papers.map { |k,v| v }.flatten
    # p papers
    p papers.length
  end

  # ruby -I lib/ test/test_sparql.rb --name test_japan_2019
  def test_japan_2019
    bh2019 = @@biohackathons['Japan2019']
    # p @@papers
    # [#<OpenStruct title="Data validation and schema interoperability", url="https://biohackrxiv.org/8qdse", date="2020-04-07", authors=["Leyla Garcia", "Jerven Bolleman", "Michel Dumontier", "Simon Jupp", "Jose Emilio Labra Gayo", "Thomas Liener", "Tazro Ohta", "N\u00FAria Queralt-Rosinach", "Chunlei Wu"]>, #<OpenStruct title="Logic Programming for the Biomedical Sciences", url="https://biohackrxiv.org/km9ux", date="2020-04-10", authors=["Chris Mungall", "Hirokazu Chiba", "Shuichi Kawashima", "Yasunori Yamamoto", "Pjotr Prins", "Nada Amin", "Deepak Unni", "<nobr>William&nbsp;E.&nbsp;Byrd</nobr>"]>]
    papers = @@papers['Japan2019']
    assert_equal 2,papers.length
  end

  def test_count_authors
    count = BHXIVUtils::PaperList.count_authors()
    print("COUNT:",count)
    assert(count > 100)
  end
end
