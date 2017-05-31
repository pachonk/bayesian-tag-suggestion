require 'set'
require_relative 'link.rb'
require_relative 'tokenizer.rb'
require 'byebug'

class LinkTrainer
  Classification = Struct.new(:guess, :score)
  attr_accessor :to_train
  attr_reader :totals, :categories

  def initialize(training_file)
    setup!(training_file)
  end

  # training_file is an array of tags and url strings
  # this gets all the different tags
  def setup!(training_file)
    @tags = Set.new
    links = Array.new
    @to_train = Array.new
    @keywords_for_tag = Hash.new { |h, k| h[k] = Set.new }

    # Splits each line into the tags
    training_file.each_line do |tf|
      tags = tf.split(/#|https?:\/\//).map(&:split).first
      url = tf.split(/#|https?:\/\//).map(&:split).last.to_s.tr('["', '').tr('"]', '')

      link = Link.new(url, tags)
      @to_train << link
      links << link

      tags.each do |t|
        @tags << t
      end
    end

    @totals = Hash[@tags.map{ |t|
      [t, 0]
    }]

    @totals.default = 0
    @totals['_all'] = 0

    @training = Hash[@tags.map { |t| [t, Hash.new(0)]}]
    links.each do |l|
      write(l)
    end
  end

  def total_for(tag)
    @totals.fetch(tag)
  end

  def train!
    @to_train.each do |link|
      write(link)
    end

    @to_train = []
  end

  def write(link)
    tags = link.tags
    url = link.url

    if url.nil?
      return
    end

    # Tokenizes a URL into pieces
    # EG: codinghorror.com -> coding horror
    # Not the best approach but it works for now
    # Not implemented, just puts a URL right now
    
    token = Tokenizer.tokenize("http://#{url}")

    throw 'error' if token.nil?

    tags.each do |tag|
      @training[tag][token] += 1
      @totals['_all'] += 1
      # Add the token(s) to the tag
      @keywords_for_tag[tag] << token
    end
  end

  def get(tag, token)
    @training[tag][token].to_i
  end

  def total
    sum = 0
    @keywords_for_tag.each_key {|key|
      sum += @keywords_for_tag[key].count
    }
    sum
  end

  # Not really working
  # Different strategies could include similiar sequential characters in a link
  # or substrings that overlap
  def score(link)
    train!
    url = link.url
    tag_totals = @totals

    aggregates = Hash[@tags.map do |t|
      [
        t,
        Rational(@keywords_for_tag[t].count, total)
      ]
    end]
    token = Tokenizer.tokenize(url)

    @tags.each do |tag|
      # r needs to be the percentage matched between the link and any link in a tag
      min = 0
      # byebug
      if @keywords_for_tag[tag].include?(token)
        min = 1
      end
      r = Rational(@keywords_for_tag[tag].count, total)
      aggregates[tag] *= r
    end

    aggregates
  end

  def normalized_score(url)
    score = score(url)
    sum = score.values.inject(&:+)

    Hash[score.map do |tag, aggregate|
      [tag, (aggregate / sum).to_f]
    end]
  end

  def preference
    @tags.sort_by {|t| total_for(t)}
  end

  def classify(link)
    score = score(link)
    p score
    max_score = 0.0
    max_key = preference.last

    score.each do |k, v|
      if v > max_score
        max_key = k
        max_score = v
      elsif v == max_score && preference.index(k) < preference.index(max_key)
        max_key = k
        max_score = v
      else
      end
    end
    throw 'error' if max_key.nil?
    Classification.new(max_key, max_score)
  end
end
