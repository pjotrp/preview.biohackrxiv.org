$LOAD_PATH << __dir__

require 'sinatra'
# require 'sinatra/json'
require 'slim'
require 'securerandom'
# require 'lib/list'  # Commented out while remote SPARQL server is unavailable
require 'logger'

$logger = Logger.new(STDOUT)
$logger.level = Logger::DEBUG

configure {
  set :server, :puma
  # :after_handler runs the `error` handlers below and only falls back to
  # Sinatra's stack-trace page when none matches -- with `true`, a readable
  # CommandError was shown as a Ruby backtrace.
  set :show_exceptions, :after_handler
  set :environment, :development
  set :logging, :true
}

class CommandError < StandardError
end

def system_log(cmd)
  $logger.debug("Invoking: #{cmd}\n")
  result = `#{cmd} 2>&1`
  status = $?.exitstatus
  result2 = result.force_encoding('utf-8')
  $logger.debug(result2)
  if status!=0
    raise CommandError, "Failed to run command: "+result2
  end
end

# Run tests on startup
system_log("cp -vau /bhxiv-gen-pdf/example /tmp/")
system_log("cd /bhxiv-gen-pdf && ruby ./bin/gen-pdf --debug /tmp/example/logic")

class BHXIV < Sinatra::Base
  helpers do
    def create_workdir(id)
      workdir = "/tmp/#{id}"
      FileUtils.mkdir(workdir)
      workdir
    end

    def stage_gitrepo(id, git_url)
      workdir = create_workdir(id)
      system_log("git clone --depth 1 -c core.askPass=echo #{git_url} #{workdir}/#{File.basename(git_url)}")
    end

    def create_outdir(id)
      outdir_path = File.dirname(__FILE__) + "/public/papers/#{id}"
      FileUtils.mkdir_p(outdir_path)
      outdir_path
    end

    # Where the staged paper is, so that the publish route can find it later
    # without guessing at the uuid directory layout.
    def staged_path(id)
      "/tmp/#{id}/staged.json"
    end

    def remember_staged(id, paper_dir, pdf_path, git_url = nil)
      File.write(staged_path(id), JSON.pretty_generate({
        'id' => id,
        'paper_dir' => paper_dir,
        'pdf' => pdf_path,
        'repository' => git_url,
        'staged' => Time.now.utc.to_s
      }))
    end

    def staged(id)
      path = staged_path(id)
      raise CommandError, "Nothing staged under #{id}" unless File.exist?(path)
      JSON.parse(File.read(path))
    end

    # xiv-publish is a tool, like gen-pdf: the transport that deposits a paper.
    # It prints its result as JSON on stdout and its progress on stderr, so the
    # service never has to know anything about Python or the Zenodo API.
    # The deposit runs with the caller's token in its environment and nothing
    # else: it is not written to a file, not kept in a cookie or the database, and
    # not logged -- only the command is, and the token is not in it.
    def submit_to_zenodo(staged_paper, token)
      command = ['xiv-publish', 'submit', staged_paper['paper_dir'], '--json']
      # The repository URL is the authoritative address of the paper: it is what
      # the submitter handed over, where the git_url in the paper's own header is
      # a claim the author can leave stale.
      # A repository URL is the authoritative address; anything else (a local
      # path, an ssh remote) is provenance rather than an address a reader can
      # follow, so it is recorded as where it came from instead.
      repository = staged_paper['repository'].to_s
      if repository.match?(%r{\A(https?://|git@)})
        command += ['--repo-url', repository]
      elsif !repository.empty?
        command += ['--source', "repo:#{repository}"]
      end
      $logger.debug("Invoking: #{command.join(' ')}")
      stdout, stderr, status = Open3.capture3({'ZENODO_TOKEN' => token}, *command)
      # stderr can carry an API error message; it never carries the token.
      $logger.debug(stderr)
      raise CommandError, "xiv-publish failed: #{stderr}#{stdout}" unless status.success?
      JSON.parse(stdout)
    rescue JSON::ParserError => e
      raise CommandError, "xiv-publish did not return JSON: #{e.message}"
    end

    def preview(id)
      @id = id
      @staged = staged(id)
      @paper_dir = @staged['paper_dir']
    end

    def cleanup(id, pdf_path)
      FileUtils.rm_rf("/tmp/#{id}")
      # staged.json holds the absolute path the renderer wrote to
      # (<workdir>/public/papers/<uuid>/paper.pdf), not the URL, so the directory
      # to remove is its dirname -- as long as it really is inside public/.
      served = File.dirname(pdf_path.to_s)
      root = File.join(settings.public_folder, 'papers')
      FileUtils.rm_rf(served) if served.start_with?(root)
    rescue StandardError => e
      # A leftover directory is not worth failing a successful deposit over.
      $logger.debug("cleanup of #{id} failed: #{e.message}")
    end

    def gen_pdf(id, git_url = nil)
      # Find paper.md
      glob = "/tmp/#{id}/**/paper.md"
      $logger.debug(glob)
      files = Dir.glob(glob)
      if files.size < 1
        raise CommandError, "Can not find a paper.md in directory structure!"
      end
      paper_dir = File.dirname(files.first)
      # Prepare output dir
      outdir = create_outdir(id)
      pdf_path = "#{outdir}/paper.pdf"
      # Generate
      system_log("gen-pdf #{paper_dir} #{pdf_path}")
      remember_staged(id, paper_dir, pdf_path, git_url)
      # Return pdf_path      "/papers/#{id}/paper.pdf"
      "/papers/#{id}/paper.pdf"
    end
  end

  configure do
    set :root, File.dirname(__FILE__)
    set :protection, :except => [:json_csrf]

    # Commented out while remote SPARQL server is unavailable
    # set :events, BHXIVUtils::PaperList.biohackathon_events()
    # set :all_papers, BHXIVUtils::PaperList.all_papers(settings.events)
    # set :all_papers_expanded, BHXIVUtils::PaperList.expand_authors(settings.all_papers)

    # set :count_events, settings.events.length
    # set :count_papers, settings.all_papers.map { |k,v| v }.flatten.length
    # set :count_authors, BHXIVUtils::PaperList.count_authors()

    # Temporary fallback values
    set :events, {}
    set :all_papers, {}
    set :all_papers_expanded, {}
    set :count_events, 0
    set :count_papers, 0
    set :count_authors, 0
  end

  error CommandError do
    # 'Sorry there was a nasty error - ' + env['sinatra.error'].message
    @error_msg = env['sinatra.error'].message
    slim :error
  end

  error do
    'Server error: ' + env['sinatra.error'].message
  end

  get '/' do
    # Commented out while remote SPARQL server is unavailable
    # @biohackathons = settings.events
    # @papers = settings.all_papers
    # @count_events = settings.count_events
    # @count_papers = settings.count_papers
    # @count_authors = settings.count_authors

    # Temporary fallback values
    @biohackathons = {}
    @papers = {}
    @count_events = 0
    @count_papers = 0
    @count_authors = 0
    slim :index
  end

  post '/gen-pdf' do
    # Only a repository URL is accepted: a paper is deposited from a repository,
    # so that the record can name it and a later submission can find it again.
    $logger.debug(params)
    git_url = params[:repository].to_s.strip
    if git_url.empty?
      status 400
      @error_msg = 'Please provide the URL of the repository that holds your paper.md. ' \
                   'A paper is deposited from its repository, so that the record can ' \
                   'name it and a later submission can find it again.'
      halt slim(:error)
    end

    id = SecureRandom.uuid
    begin
      stage_gitrepo(id, git_url)
      pdf_path = gen_pdf(id, git_url)
    rescue CommandError => e
      status 502
      @error_msg = e.message
      halt slim(:error)
    end

    if pdf_path
      # Show the PDF in a frame with a Submit button rather than sending the PDF
      # itself: publishing is a decision, and it belongs on the preview.
      redirect "/papers/#{File.basename(File.dirname(pdf_path))}"
    else
      status 500
    end
  end

  get '/papers/:id' do
    @id = params[:id]
    preview(@id)
    slim :paper
  end

  # The deposit asks for the caller's Zenodo token first: the record belongs in
  # their account, and this service has no business holding a token of its own.
  get '/papers/:id/submit' do
    @id = params[:id]
    preview(@id)
    slim :token
  end

  # Publishing runs the transport and renders the outcome on the same page.
  # Deliberately not a redirect through a session: the answer belongs to the
  # request that asked for it, and a half-remembered flash message is how a
  # publish looks like it did nothing.
  post '/publish/:id' do
    @id = params[:id]
    preview(@id)
    token = params[:token].to_s.strip
    if token.empty?
      @error = 'A Zenodo personal access token is needed to deposit this paper.'
      halt slim(:token)
    end
    begin
      @result = submit_to_zenodo(@staged, token)
      # The record holds the PDF now, so the staged copy and the served one are
      # done with: that is the only thing that ever cleans them up.
      cleanup(@id, @staged['pdf'])
      @cleaned = true
    rescue CommandError => e
      @error = e.message
    end
    slim :paper
  end

  # Commented out while remote SPARQL server is unavailable
  # get '/list.json' do
  #   content_type :json
  #   h = BHXIVUtils::PaperList.to_h(settings.events, settings.all_papers_expanded)
  #   JSON(h)
  # end

  # get '/list' do
  #   @biohackathons = settings.events
  #   @papers = settings.all_papers
  #   # expand authors (we could have done this more lazily)
  #   @papers = settings.all_papers_expanded
  #   @count_events = settings.count_events
  #   @count_papers = settings.count_papers
  #   @count_authors = settings.count_authors
  #   slim :list
  # end
end
