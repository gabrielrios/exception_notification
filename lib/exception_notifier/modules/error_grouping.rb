require 'active_support/core_ext/numeric/time'

module ErrorGrouping

  def self.included(base)
    base.extend ClassMethods

    base.class_eval do
      mattr_accessor :error_grouping
      self.error_grouping = false

      mattr_accessor :error_grouping_period
      self.error_grouping_period = 5.minutes

      mattr_accessor :error_grouping_cache
    end
  end

  module ClassMethods
    # Fallback to the memory store while the specified cache store doesn't work
    #
    def fallback_cache_store
      @fallback_cache_store ||= ActiveSupport::Cache::MemoryStore.new
    end

    def error_count(error_key)
      count = begin
        error_grouping_cache.read(error_key)
      rescue => e
        Rails.logger.warn("#{error_grouping_cache.inspect} failed to read, reason: #{e.message}. Falling back to memory cache store.")
        fallback_cache_store.read(error_key)
      end

      count.to_i if count
    end

    def save_error_count(error_key, count)
      error_grouping_cache.write(error_key, count, expires_in: error_grouping_period)
    rescue => e
      Rails.logger.warn("#{error_grouping_cache.inspect} failed to write, reason: #{e.message}. Falling back to memory cache store.")
      fallback_cache_store.write(error_key, count, expires_in: error_grouping_period)
    end

    def group_error!(exception, options)
      message_based_key = %Q[exception:#{Zlib.crc32("#{exception.class.name}\nmessage:#{exception.message}")}]
      accumulated_errors_count = 1

      if count = error_count(message_based_key)
        accumulated_errors_count = count + 1
        save_error_count(message_based_key, accumulated_errors_count)
      else
        backtrace_based_key = %Q[exception:#{Zlib.crc32("#{exception.class.name}\npath:#{exception.backtrace.try(:first)}")}]

        if count = Rails.cache.read(backtrace_based_key)
          accumulated_errors_count = count + 1
          save_error_count(backtrace_based_key, accumulated_errors_count)
        else
          save_error_count(backtrace_based_key, accumulated_errors_count)
          save_error_count(message_based_key, accumulated_errors_count)
        end
      end

      options[:accumulated_errors_count] = accumulated_errors_count
    end

    def send_notification?(exception, count)
      factor = Math.log2(count)
      factor.to_i == factor
    end
  end
end
