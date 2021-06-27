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
  def test_authors
    # paper = "https://biohackrxiv.org/wu9et"
    paper = "https://biohackrxiv.org/km9ux"
    print(BHXIVUtils::PaperList.author_query(paper))
    authors = BHXIVUtils::PaperList.sparql(BHXIVUtils::PaperList.author_query(paper),lambda{|author| author[:author] })
    assert_equal ["Chris Mungall", "Hirokazu Chiba", "Shuichi Kawashima", "Yasunori Yamamoto", "Pjotr Prins", "Nada Amin", "Deepak Unni", "<nobr>William&nbsp;E.&nbsp;Byrd</nobr>"],authors
  end

end
