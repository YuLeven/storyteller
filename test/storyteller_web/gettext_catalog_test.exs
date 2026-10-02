defmodule StorytellerWeb.GettextCatalogTest do
  use ExUnit.Case, async: true

  alias Expo.Message.Plural
  alias Expo.Message.Singular

  @catalog_root Path.expand("../../priv/gettext", __DIR__)
  @locales ["es", "fr"]
  @domains ["default", "errors"]

  test "Spanish and French catalogs translate every active message" do
    missing_translations =
      for locale <- @locales,
          domain <- @domains,
          message <- catalog_messages(locale, domain),
          missing <- empty_translations(message),
          do: Map.merge(missing, %{locale: locale, domain: domain})

    details =
      Enum.map_join(missing_translations, "\n", fn missing ->
        form = if missing.form == :singular, do: "", else: " plural form #{missing.form}"

        "- #{missing.locale}/#{missing.domain}: #{inspect(missing.msgid)}#{form}"
      end)

    assert missing_translations == [], "Untranslated catalog entries:\n#{details}"
  end

  test "catalog scan ignores the header and checks each plural translation" do
    catalog =
      Expo.PO.parse_string!("""
      msgid ""
      msgstr ""
      "Language: es\\n"

      msgid "Translated"
      msgstr "Traducido"

      msgid "Missing singular"
      msgstr ""

      msgid "One item"
      msgid_plural "Many items"
      msgstr[0] "Un elemento"
      msgstr[1] ""
      """)

    missing_translations =
      catalog.messages
      |> Enum.reject(&(message_id(&1) == ""))
      |> Enum.flat_map(&empty_translations/1)

    assert missing_translations == [
             %{msgid: "Missing singular", form: :singular},
             %{msgid: "One item", form: 1}
           ]
  end

  defp catalog_messages(locale, domain) do
    path = Path.join([@catalog_root, locale, "LC_MESSAGES", "#{domain}.po"])

    path
    |> Expo.PO.parse_file!()
    |> Map.fetch!(:messages)
    |> Enum.reject(& &1.obsolete)
    |> Enum.reject(&(message_id(&1) == ""))
  end

  defp empty_translations(%Singular{msgid: msgid, msgstr: msgstr}) do
    if blank?(msgstr), do: [%{msgid: IO.iodata_to_binary(msgid), form: :singular}], else: []
  end

  defp empty_translations(%Plural{msgid: msgid, msgstr: translations}) do
    msgid = IO.iodata_to_binary(msgid)

    translations
    |> Enum.flat_map(fn {index, translation} ->
      if blank?(translation), do: [%{msgid: msgid, form: index}], else: []
    end)
    |> Enum.sort_by(& &1.form)
  end

  defp message_id(%Singular{msgid: msgid}), do: IO.iodata_to_binary(msgid)
  defp message_id(%Plural{msgid: msgid}), do: IO.iodata_to_binary(msgid)

  defp blank?(translation) do
    String.trim(IO.iodata_to_binary(translation)) == ""
  end
end
