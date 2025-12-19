Rails.application.configure do
  MissionControl::Jobs.http_basic_auth_user = ENV.fetch("MISSION_CONTROL_AUTH_USER", "admin")
  MissionControl::Jobs.http_basic_auth_password = ENV.fetch("MISSION_CONTROL_AUTH_PASSWORD", "admin")
end
