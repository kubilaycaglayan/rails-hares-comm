Rails.application.reloader.to_prepare do
  RMQ_ACTOR = Rabactor.instance
end

