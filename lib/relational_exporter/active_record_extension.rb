module ActiveRecordExtension
  extend ActiveSupport::Concern

  def find_all_by_scope(scope_hash={})
    scope_hash = { where: {} } if scope_hash.nil?
    the_scope = nil
    scope_hash.each do |method, scoping|
      if the_scope.nil?
        the_scope = send method.to_sym, scoping
      else
        the_scope.send method.to_sym, scoping
      end
    end
    the_scope
  end

  def set_scope_from_hash(scope_hash={}, clear_default_scope=false)
    scope_hash = {} if scope_hash.nil?
    clear_default_scopes if clear_default_scope

    result = nil
    scope_hash.each do |method, scoping|
      if result.nil?
        result = send method.to_sym, scoping
      else
        result.send method.to_sym, scoping
      end
    end

    default_scope { result }
  end

  def clear_default_scopes
    self.default_scopes = []
  end
end

ActiveRecord::Base.send(:extend, ActiveRecordExtension)