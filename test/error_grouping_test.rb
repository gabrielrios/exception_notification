require 'test_helper'

class ErrorGroupTest < ActiveSupport::TestCase

  setup do
    module TestModule
      include ExceptionNotifier::ErrorGrouping
      FileUtils.mkdir_p "test/dummy/tmp/cache"
      @@error_grouping_cache = ActiveSupport::Cache::FileStore.new("test/dummy/tmp/cache")
    end

    @exception = RuntimeError.new("ERROR")
    @exception.stubs(:backtrace).returns(["/path/where/error/raised:1"])

    @exception2 = RuntimeError.new("ERROR2")
    @exception2.stubs(:backtrace).returns(["/path/where/error/found:2"])
  end

  teardown do
    TestModule.error_grouping_cache.clear
    TestModule.fallback_cache_store.clear
  end

  test "should add additional option: error_grouping_cache" do
    assert_respond_to TestModule, :error_grouping_cache
    assert_respond_to TestModule, :error_grouping_cache=
  end

  test "should return errors count nil when not same error for .error_count" do
    assert_nil TestModule.error_count("something")
  end

  test "should return errors count when same error for .error_count" do
    TestModule.error_grouping_cache.write("error_key", 13)
    assert_equal 13, TestModule.error_count("error_key")
  end

  test "should fallback to memory store cache if specified cache store failed to read" do
    TestModule.error_grouping_cache.stubs(:read).raises(RuntimeError.new "Failed to read")
    original_fallback = TestModule.fallback_cache_store
    TestModule.expects(:fallback_cache_store).returns(original_fallback).at_least_once

    assert_nil TestModule.error_count("something_to_read")
  end

  test "should save error with count for .save_error_count" do
    count = rand(1..10)

    TestModule.save_error_count("error_key", count)
    assert_equal count, TestModule.error_grouping_cache.read("error_key")
  end

  test "should fallback to memory store cache if specified cache store failed to write" do
    TestModule.error_grouping_cache.stubs(:write).raises(RuntimeError.new "Failed to write")
    original_fallback = TestModule.fallback_cache_store
    TestModule.expects(:fallback_cache_store).returns(original_fallback).at_least_once

    assert TestModule.save_error_count("something_to_cache", rand(1..10))
  end

  test "should save accumulated_errors_count into options" do
    options = {}
    TestModule.group_error!(@exception, options)

    assert_equal 1, options[:accumulated_errors_count]
  end

  test "should not group error if different exception in .group_error!" do
    options1 = {}
    TestModule.expects(:save_error_count).with{|key, count| key.is_a?(String) && count == 1}.times(4).returns(true)
    TestModule.group_error!(@exception, options1)

    options2 = {}
    TestModule.group_error!(NoMethodError.new("method not found"), options2)

    assert_equal 1, options1[:accumulated_errors_count]
    assert_equal 1, options2[:accumulated_errors_count]
  end

  test "should not group error is same exception but different message or backtrace" do
    options1 = {}
    TestModule.expects(:save_error_count).with{|key, count| key.is_a?(String) && count == 1}.times(4).returns(true)
    TestModule.group_error!(@exception, options1)

    options2 = {}
    TestModule.group_error!(@exception2, options2)

    assert_equal 1, options1[:accumulated_errors_count]
    assert_equal 1, options2[:accumulated_errors_count]
  end

  test "should group error if same exception and message" do
    options = {}

    10.times do |i|
      @exception2.stubs(:backtrace).returns(["/path:#{i}"])
      TestModule.group_error!(@exception2, options)
    end

    assert_equal 10, options[:accumulated_errors_count]
  end

  test "should group error if same exception and backtrace" do
    options = {}

    10.times do |i|
      @exception2.stubs(:message).returns("ERRORS#{i}")
      TestModule.group_error!(@exception2, options)
    end

    assert_equal 10, options[:accumulated_errors_count]
  end

  test "should group error by that message have high priority" do
    message_based_key = "exception:#{Zlib.crc32("RuntimeError\nmessage:ERROR")}"
    backtrace_based_key = "exception:#{Zlib.crc32("RuntimeError\n/path/where/error/raised:1")}"

    TestModule.save_error_count(message_based_key, 1)
    TestModule.save_error_count(backtrace_based_key, 1)

    TestModule.expects(:save_error_count).with(message_based_key, 2).once
    TestModule.expects(:save_error_count).with(backtrace_based_key, 2).never

    TestModule.group_error!(@exception, {})
  end
end
