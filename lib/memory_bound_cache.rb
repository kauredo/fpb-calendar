# Option 1: Modify the cache class to store data + timestamp
class MemoryBoundCache
  def initialize(max_items = 30)
    @cache = {}
    @access_times = {}
    @max_items = max_items
    @timestamps = {} # Add timestamp storage
  end

  def [](key)
    return unless @cache.has_key?(key)

    @access_times[key] = Time.now
    @cache[key]
  end

  def []=(key, value)
    if @cache.size >= @max_items && !@cache.has_key?(key)
      # Remove least recently used item
      lru_key = @access_times.min_by { |_, time| time }[0]
      @cache.delete(lru_key)
      @access_times.delete(lru_key)
      @timestamps.delete(lru_key)  # Also delete the timestamp
    end
    @cache[key] = value
    @access_times[key] = Time.now
    @timestamps[key] = Time.now    # Set timestamp when value is set
  end

  def timestamp(key)
    @timestamps[key]
  end

  def has_key?(key)
    @cache.has_key?(key)
  end

  def clear
    @cache.clear
    @access_times.clear
    @timestamps.clear
  end

  def size
    @cache.size
  end

  # For debugging
  def keys
    @cache.keys
  end
end
