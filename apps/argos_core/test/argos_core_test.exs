defmodule ArgosCoreTest do
  use ExUnit.Case
  doctest ArgosCore

  test "mailer creates email based on configuration" do
    subject = "Test subject"
    body = "Test body"

    %{
      subject: ^subject,
      text_body: ^body,
      from: from,
      to: to
      } =
      %{subject: "Test subject", text_body: "Test body"}
      |> ArgosCore.Mailer.send_email()

    assert Application.get_env(:argos_core, :mail_sender) == from
    assert Application.get_env(:argos_core, :mail_recipient) == to
  end
end
