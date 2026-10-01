defmodule Storyteller.GM.ContextBudget do
  @moduledoc """
  Builds a deterministic, relevance-ranked GM context within an input budget.

  Before the provider returns its authoritative token count, UTF-8 bytes in the
  exact instruction and context text form a conservative upper bound for the
  byte-pair tokenizers used by the supported OpenAI models. A fixed allowance
  covers request framing. Completed Responses usage is recorded separately.
  """

  @default_budget 24_000
  @framing_allowance 512
  @recent_history_count 12
  @relevant_history_count 8
  @recent_event_text_chars 1_600
  @relevant_event_text_chars 900
  @memory_summary_chars 1_500
  @detailed_continuity_count 12
  @memory_stopwords MapSet.new(~w(
    a about above after again against all am an and any are as at be because been before being
    below between both but by can could did do does doing down during each few for from further
    had has have having he her here hers herself him himself his how i if in into is it its
    itself just me more most my myself no nor not of off on once only or other our ours ourselves
    out over own same she should so some such than that the their theirs them themselves then
    there these they this those through to too under until up very was we were what when where
    which while who whom why with would you your
    a al algo algunas algunos ante antes como con contra cual cuando de del desde donde durante
    e el ella ellas ellos en entre era erais eran eras eres es esa esas ese eso esos esta estaba
    estaban estado estas este esto estos fue fueron ha habia hacia han hasta hay la las le les lo
    los mas me mi mis mucho muy nada ni no nos o otra otras otro otros para pero poco por porque
    que quien se sin sobre su sus te tiene todo tu tus un una unas uno unos y ya
    au aux avec ce ces dans de des du elle en et eux il je la le les leur lui ma mais me meme mes
    moi mon ne nos notre nous on ou par pas pour qu que quelle qui sa se ses son sur ta te tes toi
    ton tu un une vos votre vous y
  ))

  @measured_sections [
    :campaign,
    :world,
    :inventory,
    :places,
    :travel_connections,
    :objectives,
    :memory,
    :continuity,
    :characters,
    :panels,
    :history
  ]

  @section_metric_keys %{
    campaign: :section_campaign_bytes,
    world: :section_world_bytes,
    inventory: :section_inventory_bytes,
    places: :section_places_bytes,
    travel_connections: :section_travel_connections_bytes,
    objectives: :section_objectives_bytes,
    memory: :section_memory_bytes,
    continuity: :section_continuity_bytes,
    characters: :section_characters_bytes,
    panels: :section_panels_bytes,
    history: :section_history_bytes
  }

  @doc "Returns a compact context and safe size metrics, or a recoverable budget error."
  def compile(context, instructions, model, opts \\ [])

  def compile(context, instructions, model, opts)
      when is_map(context) and is_binary(instructions) do
    budget = token_budget(model, opts)
    {selected_context, retrieval_omitted?} = retrieve_player_managed_memory(context)

    selected_context =
      if retrieval_omitted? do
        context_with_completeness(selected_context, %{
          player_managed_memory_details_omitted: true
        })
      else
        selected_context
      end

    retrieval_omissions =
      if retrieval_omitted?, do: [:player_managed_memory_details], else: []

    full =
      measure(
        selected_context,
        instructions,
        budget,
        retrieval_omitted?,
        retrieval_omissions
      )

    cond do
      full.conservative_input_token_upper_bound <= budget ->
        {:ok, %{context: selected_context, metrics: full}}

      true ->
        compacted = compact_context(selected_context)
        omissions = Enum.uniq(retrieval_omissions ++ compacted.omissions)
        metrics = measure(compacted.context, instructions, budget, true, omissions)

        if metrics.conservative_input_token_upper_bound <= budget do
          {:ok, %{context: compacted.context, metrics: metrics}}
        else
          emit_metrics(metrics)
          {:error, :context_budget_exceeded}
        end
    end
  rescue
    _error -> {:error, :context_budget_exceeded}
  end

  def compile(_context, _instructions, _model, _opts),
    do: {:error, :context_budget_exceeded}

  @doc "Emits only numeric size/usage data; campaign text and identifiers are never attached."
  def emit_metrics(metrics, provider_usage \\ %{})

  def emit_metrics(metrics, provider_usage) when is_map(metrics) do
    usage = if is_map(provider_usage), do: provider_usage, else: %{}

    measurements =
      metrics
      |> Map.take([
        :budget_tokens,
        :conservative_input_token_upper_bound,
        :instructions_bytes,
        :context_json_bytes
      ])
      |> Map.merge(metrics.section_bytes)
      |> maybe_put(:provider_input_tokens, non_negative_integer(usage[:input_tokens]))
      |> maybe_put(:provider_output_tokens, non_negative_integer(usage[:output_tokens]))

    :telemetry.execute([:storyteller, :gm, :context], measurements, %{})
    :ok
  rescue
    _error -> :ok
  end

  def emit_metrics(_metrics, _provider_usage), do: :ok

  defp token_budget(model, opts) do
    configured = Application.get_env(:storyteller, :gm_context_token_budgets, %{})

    budget =
      Keyword.get(opts, :context_input_token_budget) ||
        Map.get(configured, model, Map.get(configured, "default", @default_budget))

    if is_integer(budget) and budget > 0, do: budget, else: 0
  end

  defp measure(context, instructions, budget, compacted?, omissions) do
    context_json = Jason.encode!(context)

    section_bytes =
      Map.new(@measured_sections, fn section ->
        value = Map.get(context, section, Map.get(context, Atom.to_string(section)))
        {metric_key(section), byte_size(Jason.encode!(value))}
      end)

    instructions_bytes = byte_size(instructions)
    context_json_bytes = byte_size(context_json)

    %{
      budget_tokens: budget,
      instructions_bytes: instructions_bytes,
      context_json_bytes: context_json_bytes,
      conservative_input_token_upper_bound:
        instructions_bytes + context_json_bytes + @framing_allowance,
      section_bytes: section_bytes,
      compacted?: compacted?,
      omissions: omissions
    }
  end

  defp metric_key(section), do: Map.fetch!(@section_metric_keys, section)

  defp compact_context(context) do
    terms = query_terms(context)
    player_place_id = player_place_id(context)

    {history, history_omitted?} =
      compact_history(Map.get(context, "history", context[:history]), terms)

    {characters, profiles_omitted?} =
      compact_characters(
        Map.get(context, "characters", context[:characters]),
        terms,
        player_place_id
      )

    {places, place_details_omitted?} =
      compact_places(
        Map.get(context, "places", context[:places]),
        terms,
        player_place_id,
        context
      )

    {continuity, continuity_details_omitted?} =
      compact_continuity(Map.get(context, "continuity", context[:continuity]), terms)

    {objectives, objective_details_omitted?} =
      compact_objectives(Map.get(context, "objectives", context[:objectives]), terms)

    {memory, memory_omitted?} = compact_memory(Map.get(context, "memory", context[:memory]))

    omissions =
      [
        history: history_omitted?,
        remote_character_profiles: profiles_omitted?,
        remote_place_details: place_details_omitted?,
        continuity_details: continuity_details_omitted?,
        closed_objective_details: objective_details_omitted?,
        memory_summary: memory_omitted?
      ]
      |> Enum.filter(fn {_key, omitted?} -> omitted? end)
      |> Enum.map(&elem(&1, 0))

    compacted =
      context
      |> put_context_value("history", history)
      |> put_context_value("characters", characters)
      |> put_context_value("places", places)
      |> put_context_value("continuity", continuity)
      |> put_context_value("objectives", objectives)
      |> put_context_value("memory", memory)

    if omissions == [] do
      %{context: compacted, omissions: []}
    else
      completeness = %{
        history_compacted: history_omitted?,
        remote_character_profiles_omitted: profiles_omitted?,
        remote_place_details_omitted: place_details_omitted?,
        continuity_details_omitted: continuity_details_omitted?,
        closed_objective_details_omitted: objective_details_omitted?,
        memory_summary_compacted: memory_omitted?
      }

      %{context: context_with_completeness(compacted, completeness), omissions: omissions}
    end
  end

  defp context_with_completeness(context, completeness),
    do:
      Map.update(
        context,
        :context_completeness,
        completeness,
        &Map.merge(&1, completeness)
      )

  # Player-managed public story notes are deliberately opt-in by relevance.
  # Keep only stable identity/status metadata in context, and omit unrelated
  # note content even when the whole request fits under the size ceiling. The
  # campaign board remains the complete, player-visible source of these notes.
  defp retrieve_player_managed_memory(context) do
    continuity = value(context, :continuity)

    if is_map(continuity) do
      terms = query_terms(context)
      public_key = if Map.has_key?(continuity, "public"), do: "public", else: :public
      entries = Map.get(continuity, public_key)

      if is_list(entries) do
        {selected, omitted?} =
          Enum.map_reduce(entries, false, fn entry, any_omitted? ->
            player_managed? = value(entry, :player_managed) == true
            relevant? = memory_relevant?(entry, terms)

            if player_managed? and not relevant? and is_map(entry) do
              {Map.take(
                 entry,
                 [
                   :entry_id,
                   :kind,
                   :status,
                   :visibility,
                   :player_managed,
                   "entry_id",
                   "kind",
                   "status",
                   "visibility",
                   "player_managed"
                 ]
               ), true}
            else
              {entry, any_omitted?}
            end
          end)

        continuity = put_context_value(continuity, Atom.to_string(public_key), selected)
        {put_context_value(context, "continuity", continuity), omitted?}
      else
        {context, false}
      end
    else
      {context, false}
    end
  end

  defp memory_relevant?(entry, query_terms) do
    meaningful_query_terms = MapSet.difference(query_terms, @memory_stopwords)
    note_terms = meaningful_terms(entry_text(entry))
    not MapSet.disjoint?(meaningful_query_terms, note_terms)
  end

  defp meaningful_terms(text) when is_binary(text) do
    text
    |> String.downcase()
    |> then(&Regex.scan(~r/[\p{L}\p{N}]{3,}/u, &1))
    |> List.flatten()
    |> Enum.reject(&MapSet.member?(@memory_stopwords, &1))
    |> MapSet.new()
  end

  defp meaningful_terms(_text), do: MapSet.new()

  defp compact_history(history, terms) when is_list(history) do
    story_events = Enum.filter(history, &conversation_event?/1)
    recent = Enum.take(story_events, -@recent_history_count)
    recent_sequences = MapSet.new(recent, &event_sequence/1)

    relevant_older =
      story_events
      |> Enum.reject(&MapSet.member?(recent_sequences, event_sequence(&1)))
      |> Enum.map(&{relevance_score(event_text(&1), terms), &1})
      |> Enum.filter(&(elem(&1, 0) > 0))
      |> Enum.sort_by(fn {score, event} -> {-score, -event_sequence(event)} end)
      |> Enum.take(@relevant_history_count)
      |> Enum.map(&elem(&1, 1))

    selected =
      relevant_older
      |> Enum.map(&compact_event(&1, @relevant_event_text_chars))
      |> Kernel.++(Enum.map(recent, &compact_event(&1, @recent_event_text_chars)))
      |> Enum.sort_by(&event_sequence/1)

    omitted? = length(selected) < length(history) or selected != history
    {selected, omitted?}
  end

  defp compact_history(history, _terms), do: {history, false}

  defp conversation_event?(event) when is_map(event) do
    type = Map.get(event, "event_type", Map.get(event, :event_type))
    type = if is_atom(type), do: Atom.to_string(type), else: type

    type in ~w(player_action player_question time_passage gm_narration npc_dialogue character_activity roll_request player_roll)
  end

  defp conversation_event?(_event), do: false

  defp compact_event(event, max_text_chars) when is_map(event) do
    payload = Map.get(event, "payload", Map.get(event, :payload, %{}))
    text = if is_map(payload), do: Map.get(payload, "text", Map.get(payload, :text)), else: nil

    payload =
      if is_map(payload) do
        payload
        |> Map.take([
          "text",
          "test",
          "difficulty",
          "target",
          "result",
          "die",
          :text,
          :test,
          :difficulty,
          :target,
          :result,
          :die
        ])
        |> maybe_put_context("text", if(is_binary(text), do: compact_text(text, max_text_chars)))
      else
        %{}
      end

    event
    |> Map.take(
      ["sequence", "session_id", "event_type", "visibility", "speaker_id"] ++
        [:sequence, :session_id, :event_type, :visibility, :speaker_id]
    )
    |> put_context_value("payload", payload)
  end

  defp compact_event(event, _max_text_chars), do: event

  defp compact_characters(characters, terms, player_place_id) when is_list(characters) do
    {compacted, omitted?} =
      Enum.map_reduce(characters, false, fn character, any_omitted? ->
        speaker_id = value(character, :speaker_id)
        place_id = value(character, :current_place_id)
        mentioned? = name_mentioned?(value(character, :name), terms)

        scene_character? =
          speaker_id == "player" or (is_binary(player_place_id) and place_id == player_place_id)

        if scene_character? or mentioned? do
          {character, any_omitted?}
        else
          current_place = value(character, :current_place)

          compact =
            character
            |> Map.take([
              "speaker_id",
              "name",
              "role",
              "current_place_id",
              :speaker_id,
              :name,
              :role,
              :current_place_id
            ])
            |> maybe_put_context("current_place", compact_place_identity(current_place))

          {compact, true}
        end
      end)

    {compacted, omitted?}
  end

  defp compact_characters(characters, _terms, _player_place_id), do: {characters, false}

  defp compact_places(places, terms, player_place_id, context) when is_map(places) do
    edges = Map.get(context, "travel_connections", context[:travel_connections]) || %{}

    adjacent_ids =
      edges
      |> all_edges()
      |> Enum.flat_map(fn edge -> [value(edge, :place_a_id), value(edge, :place_b_id)] end)
      |> MapSet.new()

    {result, omitted?} =
      Enum.map_reduce(places, false, fn {visibility, place_rows}, any_omitted?
                                        when is_list(place_rows) ->
        {rows, omitted_here?} =
          Enum.map_reduce(place_rows, false, fn place, omitted_details? ->
            place_id = value(place, :place_id)

            relevant? =
              place_id == player_place_id or MapSet.member?(adjacent_ids, place_id) or
                name_mentioned?(value(place, :name), terms)

            if relevant? do
              {place, omitted_details?}
            else
              {compact_place_identity(place), true}
            end
          end)

        {{visibility, rows}, any_omitted? or omitted_here?}
      end)
      |> then(fn {groups, omitted?} -> {Map.new(groups), omitted?} end)

    {result, omitted?}
  end

  defp compact_places(places, _terms, _player_place_id, _context), do: {places, false}

  defp compact_place_identity(place) when is_map(place) do
    Map.take(place, ["place_id", "name", "visibility", :place_id, :name, :visibility])
  end

  defp compact_place_identity(_place), do: nil

  defp compact_continuity(continuity, terms) when is_map(continuity) do
    Map.new(continuity, fn {visibility, entries} ->
      entries = if is_list(entries), do: entries, else: []
      latest = Enum.take(entries, -@detailed_continuity_count)
      detailed_ids = MapSet.new(latest, &value(&1, :entry_id))

      rows =
        Enum.map(entries, fn entry ->
          active? = value(entry, :status) in ["active", :active]
          mentioned? = relevance_score(entry_text(entry), terms) > 0

          # Active continuity is canonical state, not optional history. Keep
          # its complete details even when old and lexically unrelated to the
          # current action; compacting it could silently erase durable facts.
          # Closed entries can safely lose old detail because their summary
          # identity/status remains present.
          if active? or MapSet.member?(detailed_ids, value(entry, :entry_id)) or mentioned? do
            entry
          else
            Map.drop(entry, [:details, "details"])
          end
        end)

      {visibility, rows}
    end)
    |> then(fn result ->
      omitted? = result != continuity
      {result, omitted?}
    end)
  end

  defp compact_continuity(continuity, _terms), do: {continuity, false}

  defp compact_objectives(objectives, terms) when is_map(objectives) do
    result =
      Map.new(objectives, fn {visibility, rows} ->
        rows = if is_list(rows), do: rows, else: []

        {visibility,
         Enum.map(rows, fn objective ->
           closed? =
             value(objective, :status) in ["completed", "abandoned", :completed, :abandoned]

           mentioned? = relevance_score(entry_text(objective), terms) > 0

           if closed? and not mentioned?,
             do: Map.drop(objective, [:details, "details"]),
             else: objective
         end)}
      end)

    {result, result != objectives}
  end

  defp compact_objectives(objectives, _terms), do: {objectives, false}

  defp compact_memory(memory) when is_map(memory) do
    {result, omitted?} =
      Enum.reduce(memory, {%{}, false}, fn {key, summary}, {acc, any_omitted?} ->
        {summary, omitted_here?} =
          if is_binary(summary) and String.length(summary) > @memory_summary_chars do
            {compact_text(summary, @memory_summary_chars), true}
          else
            {summary, false}
          end

        {Map.put(acc, key, summary), any_omitted? or omitted_here?}
      end)

    {result, omitted?}
  end

  defp compact_memory(memory), do: {memory, false}

  defp compact_text(text, max_chars) when is_binary(text) do
    if String.length(text) <= max_chars do
      text
    else
      prefix_length = max(max_chars - 32, 0)
      String.slice(text, 0, prefix_length) <> " … [context excerpt; older text omitted]"
    end
  end

  defp compact_text(text, _max_chars), do: text

  defp query_terms(context) do
    action = value(context, :player_action) || ""
    player_place_id = player_place_id(context)

    scene_text =
      context
      |> value(:characters)
      |> List.wrap()
      |> Enum.filter(fn character ->
        value(character, :speaker_id) == "player" or
          (is_binary(player_place_id) and value(character, :current_place_id) == player_place_id)
      end)
      |> Enum.map(&value(&1, :name))
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")

    place_text =
      context
      |> value(:places)
      |> case do
        map when is_map(map) -> Map.values(map) |> List.flatten()
        _ -> []
      end
      |> Enum.filter(&(value(&1, :place_id) == player_place_id))
      |> Enum.map(&value(&1, :name))
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")

    text = String.downcase([action, scene_text, place_text] |> Enum.join(" "))
    Regex.scan(~r/[\p{L}\p{N}]{3,}/u, text) |> List.flatten() |> MapSet.new()
  end

  defp player_place_id(context) do
    characters = value(context, :characters) || []

    case Enum.find(characters, &(value(&1, :speaker_id) == "player")) do
      nil -> nil
      player -> value(player, :current_place_id)
    end
  end

  defp all_edges(%{"public" => public, "gm_private" => private}),
    do: List.wrap(public) ++ List.wrap(private)

  defp all_edges(%{public: public, gm_private: private}),
    do: List.wrap(public) ++ List.wrap(private)

  defp all_edges(_), do: []

  defp event_text(event) do
    payload = value(event, :payload) || %{}

    [value(payload, :text), value(event, :speaker_id)]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp event_sequence(event), do: value(event, :sequence) || 0

  defp entry_text(entry) do
    [value(entry, :title), value(entry, :details)]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp relevance_score(text, terms) when is_binary(text) do
    text = String.downcase(text)
    Enum.count(terms, &String.contains?(text, &1))
  end

  defp relevance_score(_text, _terms), do: 0

  defp name_mentioned?(name, terms) when is_binary(name) do
    normalized = String.downcase(name)

    normalized != "" and MapSet.size(terms) > 0 and
      Enum.any?(terms, &String.contains?(normalized, &1))
  end

  defp name_mentioned?(_name, _terms), do: false

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, to_string(key)))
  defp value(_map, _key), do: nil

  defp put_context_value(map, key, value) when is_map(map) and is_binary(key) do
    cond do
      Map.has_key?(map, key) -> Map.put(map, key, value)
      atom_key = existing_atom_key(map, key) -> Map.put(map, atom_key, value)
      true -> Map.put(map, key, value)
    end
  end

  defp existing_atom_key(map, key) do
    atom_key = String.to_existing_atom(key)
    if Map.has_key?(map, atom_key), do: atom_key
  rescue
    ArgumentError -> nil
  end

  defp maybe_put_context(map, _key, nil), do: map
  defp maybe_put_context(map, key, value), do: put_context_value(map, key, value)

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
