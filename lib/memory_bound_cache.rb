# A simple memory-bounded cache with least recently used (LRU) eviction policy
class MemoryBoundCache
  def initialize(max_items = 30)
    @cache = {}
    @access_times = {}
    @max_items = max_items
  end

  def [](key)
    if @cache.has_key?(key)
      @access_times[key] = Time.now
      @cache[key]
    else
      nil
    end
  end

  def []=(key, value)
    if @cache.size >= @max_items && !@cache.has_key?(key)
      # Remove least recently used item
      lru_key = @access_times.min_by { |_, time| time }[0]
      @cache.delete(lru_key)
      @access_times.delete(lru_key)
    end
    @cache[key] = value
    @access_times[key] = Time.now
  end

  def has_key?(key)
    @cache.has_key?(key)
  end

  def clear
    @cache.clear
    @access_times.clear
  end

  def size
    @cache.size
  end

  # For debugging
  def keys
    @cache.keys
  end
end
