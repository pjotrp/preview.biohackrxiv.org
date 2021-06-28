#
# Run with
#
#   ruby -I lib test/test_generator.rb
#
require 'minitest'
require 'minitest/autorun'
require 'bhxiv/markdown'

class TestGenerator < MiniTest::Test
  def test_yaml_valid
    yml = md_parser('example/logic/paper.md')
    assert yml['title'] == "Logic Programming for the Biomedical Sciences"
  end

  def test_gen_1tex
    cmd = "ruby ./bin/gen-pdf --debug ./example/logic/ Other paper.tex"
    print cmd,"\n"
    print `#{cmd}`
    status = $?.exitstatus
    assert_equal 0,status
  end

  def test_gen_2pdf
    # note we can not use the --debug switch here
    cmd = "ruby ./bin/gen-pdf ./example/logic/ Japan2019 paper.pdf"
    print cmd,"\n"
    print `#{cmd}`
    status = $?.exitstatus
    assert_equal 0,status
  end
end
