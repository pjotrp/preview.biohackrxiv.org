$LOAD_PATH << __dir__

require 'sinatra'
require 'slim'
require 'securerandom'
require 'lib/list'

configure {
  set :server, :puma
}

class BHXIV < Sinatra::Base
  set :public_folder, 'public'

  helpers do
    def create_workdir(id)
      workdir = "/tmp/#{id}"
      FileUtils.mkdir(workdir)
      workdir
    end

    def stage_zipfile(id, zipfile)
      workdir = create_workdir(id)
      filepath = zipfile[:tempfile].path
      system("unzip #{filepath} -d #{workdir}")
    end

    def stage_gitrepo(id, git_url)
      workdir = create_workdir(id)
      system("git clone #{git_url} #{workdir}/#{File.basename(git_url)}")
    end

    def create_outdir(id)
      outdir_path = File.dirname(__FILE__) + "/public/papers/#{id}"
      FileUtils.mkdir_p(outdir_path)
      outdir_path
    end

    def gen_pdf(id, journal)
      # Find paper.md
      paper_dir = File.dirname(Dir.glob("/tmp/#{id}/**/paper.md").first)
      # Prepare output dir
      outdir = create_outdir(id)
      pdf_path = "#{outdir}/paper.pdf"
      # Generate
      system("ruby /gen-pdf/bin/gen-pdf #{paper_dir} #{journal} #{pdf_path}")
      # Return pdf_path
      "/papers/#{id}/paper.pdf"
    end
  end

  configure do
    set :biohackathons, BHXIVUtils::PaperList.biohackathon_events
    set :papers, Hash[settings.biohackathons.keys.map{|bh| [bh, BHXIVUtils::PaperList.bh_papers_list(bh)] }]
  end

  get '/' do
    slim :index
  end

  post '/gen-pdf' do
    # Get form parameters
    journal = params[:journal]
    git_url = params[:repository]
    zipfile = params[:zipfile]

    pdf_path = if journal
                 id = SecureRandom.uuid
                 if zipfile
                   stage_zipfile(id, zipfile)
                   gen_pdf(id, journal)
                 elsif git_url
                   stage_gitrepo(id, git_url)
                   gen_pdf(id, journal)
                 end
               end

    if pdf_path
      redirect pdf_path
    else
      status 500
    end
  end

  get '/list' do
    @biohackathons = settings.biohackathons
    @papers = settings.papers
    slim :list
  end
end
