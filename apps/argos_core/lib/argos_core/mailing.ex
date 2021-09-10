defmodule ArgosCore.Mailer do
  use Bamboo.Mailer, otp_app: :argos_core

  import Bamboo.Email

  require Logger

  def send_email(%{subject: subject, text_body: text_body}) do
    email =
      new_email(
        to: [Application.get_env(:argos_core, :mail_recipient)],
        from: [Application.get_env(:argos_core, :mail_sender)],
        subject: subject,
        text_body: text_body
      )

    case Application.get_env(:argos_core, ArgosCore.Mailer)[:username] do
      "<username>" ->
        Logger.info("Mailer not configured, would have sent the following email:")
        Logger.info(Poison.encode!(email, [pretty: true]))
        {:ok, email}
      _ ->
        email
        |> deliver_now()
    end
  end
end
