class WordCountJob < ApplicationJob
  queue_as :default

  def perform(*args)
    frequency = Hash.new(0)

    Post.all.pluck(:content).each do |content|
      content.scan(/\w+/).each { |word| frequency[word.downcase] += 1 }
    end

    Rails.cache.write('word_counts', frequency.inspect, expires_in: 20.seconds)
  end
end
