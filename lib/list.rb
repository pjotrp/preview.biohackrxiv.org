require 'net/http'
require 'json'
require 'ostruct'

module BHXIVUtils
  module PaperList
    class << self
      def gen_sparql_query(query)
        header = <<~HEREDOC
          prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>
          prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
          prefix dc: <http://purl.org/dc/terms/>
          prefix bhx: <http://biohackerxiv.org/resource/>
          prefix schema: <https://schema.org/>
        HEREDOC
        header + query
      end

      def sparql_endpoint_url(query)
        base_url = "https://sparql.genenetwork.org/sparql"
        params = "default-graph-uri=&format=application%2Fsparql-results%2Bjson&timeout=0&debug=on&run=+Run+Query+&query=#{URI.encode_www_form_component(gen_sparql_query(query))}"
        "#{base_url}/?#{params}"
      end

      def sparql(query, transform = nil)
        response = Net::HTTP.get_response(URI.parse(sparql_endpoint_url(query)))
        data = JSON.parse(response.body)
        vars = data['head']['vars']
        results = data['results']['bindings']

        results.map do |rec|
          res = {}
          vars.each do |name|
            res[name.to_sym] = rec[name]['value']
          end

          if transform
            transform.call(res)
          else
            res
          end
        end
      end

      def bh_events_list
        events_query = <<~SPARQL_EVENTS
          SELECT  ?url ?name ?date ?descr
          FROM    <https://BioHackrXiv.org/graph>
          WHERE   {
           ?url schema:name ?name ;
                dc:date ?date ;
                schema:description ?descr
          }
        SPARQL_EVENTS
        sparql(events_query)
      end

      def biohackathon_events
        biohackathons = {}
        bh_events_list.each do |rec|
          biohackathons[rec[:name]] = {
            name: rec[:name],
            url: rec[:url],
            date: rec[:date],
            descr: rec[:descr]
          }
        end
        biohackathons.sort_by { |name, rec| rec[:date] }.reverse.to_h
      end

      def papers_query(bh)
        <<~SPARQL_PAPERS
          SELECT  ?title ?url ?date
          FROM    <https://BioHackrXiv.org/graph>
          WHERE   {
            ?bh schema:name "#{bh}" .
            ?url bhx:Event ?bh ;
              dc:date ?date ;
              dc:title ?title .
          } ORDER BY ?date
        SPARQL_PAPERS
      end

      def author_query(paper_url)
        <<~SPARQL_AUTHORS
         SELECT ?author
          FROM    <https://BioHackrXiv.org/graph>
          WHERE   {
             <#{paper_url}> dc:contributor ?node .
             ?node ?p ?author .
           FILTER( !isUri(?author) ) .
           BIND (xsd:integer(REPLACE(str(?p),
           "http://www.w3.org/1999/02/22-rdf-syntax-ns#_", "")) as ?pos)
          } order by ?pos
        SPARQL_AUTHORS
      end

      def bh_papers_list(bh)
        papers = sparql(papers_query(bh), lambda{|paper| OpenStruct.new(paper) })
        papers
      end

      def all_papers(bhs)
        Hash[bhs.keys.map{|bh| [bh, BHXIVUtils::PaperList.bh_papers_list(bh)] }]
      end

      def expand_authors(papers)
        papers.each do |event,list|
          list.each do | paper |
            paper.authors = sparql(author_query(paper.url), lambda{|author| author[:author] })
          end
        end
        papers
      end

      def count_authors()
        sparql(
        <<~SPARQL
SELECT DISTINCT count(?author) as ?num
 FROM    <https://BioHackrXiv.org/graph>
 WHERE   {
    ?paper dc:contributor ?node .
    ?node ?p ?author .
  FILTER( !isUri(?author) ) .

 }
SPARQL
        # ,lambda{|r| r[:num] })
        )[0][:num].to_i
      end

      # Return record ready for JSON
      def to_h(events, papers, event=:all)
        h = {}

        events.each_pair do |name, info|
          if !papers[name].empty?
            h[name] = {
              event: name,
              descr: info[:descr]
            }
            h[name]['papers'] = []
            papers[name].each do |paps|
              h[name]['papers'].push paps.to_h
            end
          end
        end
        h
      end
    end
  end
end
