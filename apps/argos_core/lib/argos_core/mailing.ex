defmodule ArgosCore.Mailer do
  use Bamboo.Mailer, otp_app: :argos_core

  import Bamboo.Email

  require Logger

  def welcome_email do
    new_email(
      to: "simon.hohl@dainst.org",
      from: "support@myapp.com",
      subject: "Welcome to the app.",
      html_body: "<strong>Thanks for joining!</strong>",
      text_body: "Thanks for joining!"
    )
  end

  def send_welcome_email() do
    email =
      welcome_email()

    case Application.get_env(:argos_core, ArgosCore.Mailer)[:username] do
      "<username>" ->
        Logger.info("Mailer not configured, would have sent the following email:")
        Logger.info(Poison.encode!(email, [pretty: true]))
      _ ->
        email
        |> deliver_now()
    end
  end
end
