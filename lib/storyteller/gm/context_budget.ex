defmodule Storyteller.GM.ContextBudget do
  @moduledoc """
  Builds a deterministic, relevance-ranked GM context within a local
  serialized-byte limit. This is an application safety bound, not the model's
  context window, an account usage limit, or a token count. Successful
  Responses usage is recorded separately when the provider reports it.
  """

  @default_budget 24_000
  @framing_allowance 512
  @recent_history_count 12
  @relevant_history_count 8
  @max_history_scene_speakers 32
  @max_history_connected_places 24
  @recent_event_text_chars 1_600
  @relevant_event_text_chars 900
  @memory_summary_chars 1_500
  @detailed_continuity_count 12
  @max_continuity_memory_details 8
  @max_inventory_context_items 16
  @max_relevant_inventory_items 10
  @recent_inventory_context_items 6
  @max_inventory_detail_count 1
  @max_inventory_description_chars 600
  @max_inventory_properties_bytes 700
  @history_budget_fallback_tiers [
    {4, 1_600, 600},
    {4, 1_200, 400},
    {2, 800, 200},
    {1, 600, 100}
  ]
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

  # A small, explicit cross-language vocabulary for durable memory retrieval.
  # These are equivalent campaign concepts, not open-ended semantic expansion.
  @memory_term_aliases %{
    "wine" => "wine",
    "wines" => "wine",
    "vino" => "wine",
    "vinos" => "wine",
    "vin" => "wine",
    "vins" => "wine",
    "fall" => "season:autumn",
    "autumn" => "season:autumn",
    "otoño" => "season:autumn",
    "automne" => "season:autumn",
    "event" => "occasion:event",
    "events" => "occasion:event",
    "tasting" => "occasion:tasting",
    "tastings" => "occasion:tasting",
    "degustacion" => "occasion:tasting",
    "degustación" => "occasion:tasting",
    "cata" => "occasion:tasting",
    "dégustation" => "occasion:tasting",
    "evento" => "occasion:event",
    "eventos" => "occasion:event",
    "événement" => "occasion:event",
    "événements" => "occasion:event",
    "earmark" => "allocation:set-aside",
    "earmarked" => "allocation:set-aside",
    "reserve" => "allocation:set-aside",
    "reserved" => "allocation:set-aside",
    "save" => "allocation:set-aside",
    "saved" => "allocation:set-aside",
    "saving" => "allocation:set-aside",
    "aside" => "allocation:set-aside",
    "reservamos" => "allocation:set-aside",
    "guardamos" => "allocation:set-aside",
    "reservar" => "allocation:set-aside",
    "reservado" => "allocation:set-aside",
    "reservada" => "allocation:set-aside",
    "apartamos" => "allocation:set-aside",
    "apartado" => "allocation:set-aside",
    "apartada" => "allocation:set-aside",
    "separamos" => "allocation:set-aside",
    "separado" => "allocation:set-aside",
    "separada" => "allocation:set-aside",
    "réserver" => "allocation:set-aside",
    "réservé" => "allocation:set-aside",
    "réservée" => "allocation:set-aside",
    "garder" => "allocation:set-aside",
    "gardé" => "allocation:set-aside",
    "gardée" => "allocation:set-aside",
    "gardons" => "allocation:set-aside",
    "job" => "employment:work",
    "jobs" => "employment:work",
    "work" => "employment:work",
    "employment" => "employment:work",
    "employer" => "employment:work",
    "employers" => "employment:work",
    "position" => "employment:work",
    "role" => "employment:work",
    "trabajo" => "employment:work",
    "trabajos" => "employment:work",
    "empleo" => "employment:work",
    "empleos" => "employment:work",
    "empleador" => "employment:work",
    "empleadora" => "employment:work",
    "empleadores" => "employment:work",
    "puesto" => "employment:work",
    "puestos" => "employment:work",
    "travail" => "employment:work",
    "emploi" => "employment:work",
    "emplois" => "employment:work",
    "employeur" => "employment:work",
    "employeurs" => "employment:work",
    "poste" => "employment:work",
    "postes" => "employment:work",
    "hour" => "employment:terms",
    "hours" => "employment:terms",
    "working" => "employment:terms",
    "shift" => "employment:terms",
    "shifts" => "employment:terms",
    "schedule" => "employment:terms",
    "schedules" => "employment:terms",
    "timetable" => "employment:terms",
    "condition" => "employment:terms",
    "conditions" => "employment:terms",
    "term" => "employment:terms",
    "terms" => "employment:terms",
    "hora" => "employment:terms",
    "horas" => "employment:terms",
    "horario" => "employment:terms",
    "horarios" => "employment:terms",
    "jornada" => "employment:terms",
    "jornadas" => "employment:terms",
    "turno" => "employment:terms",
    "turnos" => "employment:terms",
    "condición" => "employment:terms",
    "condiciones" => "employment:terms",
    "condicion" => "employment:terms",
    "término" => "employment:terms",
    "términos" => "employment:terms",
    "termino" => "employment:terms",
    "terminos" => "employment:terms",
    "heure" => "employment:terms",
    "heures" => "employment:terms",
    "horaire" => "employment:terms",
    "horaires" => "employment:terms",
    "planning" => "employment:terms",
    "terme" => "employment:terms",
    "termes" => "employment:terms",
    "accept" => "employment:acceptance",
    "accepts" => "employment:acceptance",
    "accepted" => "employment:acceptance",
    "accepting" => "employment:acceptance",
    "acceptance" => "employment:acceptance",
    "aceptar" => "employment:acceptance",
    "acepto" => "employment:acceptance",
    "aceptas" => "employment:acceptance",
    "acepta" => "employment:acceptance",
    "aceptamos" => "employment:acceptance",
    "aceptan" => "employment:acceptance",
    "aceptado" => "employment:acceptance",
    "aceptada" => "employment:acceptance",
    "aceptacion" => "employment:acceptance",
    "aceptación" => "employment:acceptance",
    "accepter" => "employment:acceptance",
    "accepte" => "employment:acceptance",
    "accepté" => "employment:acceptance",
    "acceptée" => "employment:acceptance",
    "acceptes" => "employment:acceptance",
    "acceptez" => "employment:acceptance",
    "acceptons" => "employment:acceptance",
    "acceptant" => "employment:acceptance",
    "acceptation" => "employment:acceptance",
    "promise" => "campaign:commitment",
    "promises" => "campaign:commitment",
    "promised" => "campaign:commitment",
    "promising" => "campaign:commitment",
    "agree" => "campaign:commitment",
    "agrees" => "campaign:commitment",
    "agreed" => "campaign:commitment",
    "agreement" => "campaign:commitment",
    "acuerdo" => "campaign:commitment",
    "acuerdos" => "campaign:commitment",
    "decide" => "campaign:commitment",
    "decided" => "campaign:commitment",
    "decidir" => "campaign:commitment",
    "decidimos" => "campaign:commitment",
    "decidieron" => "campaign:commitment",
    "decidido" => "campaign:commitment",
    "decidida" => "campaign:commitment",
    "decision" => "campaign:commitment",
    "decisión" => "campaign:commitment",
    "decisiones" => "campaign:commitment",
    "plan" => "campaign:plan",
    "plans" => "campaign:plan",
    "planned" => "campaign:plan",
    "next" => "campaign:next-step",
    "upcoming" => "campaign:next-step",
    "intended" => "campaign:plan",
    "intending" => "campaign:plan",
    "intention" => "campaign:plan",
    "intentions" => "campaign:plan",
    "intención" => "campaign:plan",
    "intenciones" => "campaign:plan",
    "previsto" => "campaign:plan",
    "prevista" => "campaign:plan",
    "previstos" => "campaign:plan",
    "previstas" => "campaign:plan",
    "siguiente" => "campaign:next-step",
    "siguientes" => "campaign:next-step",
    "próximo" => "campaign:next-step",
    "próxima" => "campaign:next-step",
    "próximos" => "campaign:next-step",
    "próximas" => "campaign:next-step",
    "después" => "campaign:next-step",
    "despues" => "campaign:next-step",
    "luego" => "campaign:next-step",
    "prévu" => "campaign:plan",
    "prévue" => "campaign:plan",
    "prévus" => "campaign:plan",
    "prévues" => "campaign:plan",
    "prévoir" => "campaign:plan",
    "prevoir" => "campaign:plan",
    "ensuite" => "campaign:next-step",
    "prochain" => "campaign:next-step",
    "prochaine" => "campaign:next-step",
    "prochains" => "campaign:next-step",
    "prochaines" => "campaign:next-step",
    "suivant" => "campaign:next-step",
    "suivante" => "campaign:next-step",
    "décider" => "campaign:commitment",
    "décidé" => "campaign:commitment",
    "décidée" => "campaign:commitment",
    "décidons" => "campaign:commitment",
    "décisions" => "campaign:commitment",
    "promesa" => "campaign:commitment",
    "promesas" => "campaign:commitment",
    "prometer" => "campaign:commitment",
    "prometí" => "campaign:commitment",
    "prometi" => "campaign:commitment",
    "prometió" => "campaign:commitment",
    "prometio" => "campaign:commitment",
    "prometimos" => "campaign:commitment",
    "prometieron" => "campaign:commitment",
    "prometido" => "campaign:commitment",
    "prometida" => "campaign:commitment",
    "acordar" => "campaign:commitment",
    "acordé" => "campaign:commitment",
    "acorde" => "campaign:commitment",
    "acordó" => "campaign:commitment",
    "acordo" => "campaign:commitment",
    "acordamos" => "campaign:commitment",
    "acordaron" => "campaign:commitment",
    "promesse" => "campaign:commitment",
    "promesses" => "campaign:commitment",
    "promettre" => "campaign:commitment",
    "promis" => "campaign:commitment",
    "promet" => "campaign:commitment",
    "convenir" => "campaign:commitment",
    "convenu" => "campaign:commitment",
    "convenue" => "campaign:commitment",
    "accord" => "campaign:commitment",
    "accords" => "campaign:commitment",
    "meet" => "campaign:meeting",
    "meets" => "campaign:meeting",
    "meeting" => "campaign:meeting",
    "met" => "campaign:meeting",
    "appointment" => "campaign:meeting",
    "appointments" => "campaign:meeting",
    "rendez" => "campaign:meeting",
    "reunión" => "campaign:meeting",
    "reuniones" => "campaign:meeting",
    "reunir" => "campaign:meeting",
    "reunirse" => "campaign:meeting",
    "quedar" => "campaign:meeting",
    "quedamos" => "campaign:meeting",
    "quedaremos" => "campaign:meeting",
    "cita" => "campaign:meeting",
    "citas" => "campaign:meeting",
    "encuentro" => "campaign:meeting",
    "encontrarnos" => "campaign:meeting",
    "rencontre" => "campaign:meeting",
    "rencontrer" => "campaign:meeting",
    "rencontrent" => "campaign:meeting",
    "retrouver" => "campaign:meeting",
    "retrouvons" => "campaign:meeting",
    "retrouvent" => "campaign:meeting",
    "reply" => "campaign:response",
    "replies" => "campaign:response",
    "replied" => "campaign:response",
    "response" => "campaign:response",
    "respond" => "campaign:response",
    "responds" => "campaign:response",
    "responded" => "campaign:response",
    "answer" => "campaign:response",
    "answers" => "campaign:response",
    "answered" => "campaign:response",
    "respuesta" => "campaign:response",
    "respuestas" => "campaign:response",
    "responder" => "campaign:response",
    "responde" => "campaign:response",
    "respondió" => "campaign:response",
    "respondio" => "campaign:response",
    "contestación" => "campaign:response",
    "contestacion" => "campaign:response",
    "contestar" => "campaign:response",
    "contesta" => "campaign:response",
    "contestó" => "campaign:response",
    "contesto" => "campaign:response",
    "réponse" => "campaign:response",
    "réponses" => "campaign:response",
    "répondre" => "campaign:response",
    "répond" => "campaign:response",
    "répondu" => "campaign:response",
    "répondra" => "campaign:response",
    "pay" => "employment:compensation",
    "pays" => "employment:compensation",
    "paid" => "employment:compensation",
    "wage" => "employment:compensation",
    "wages" => "employment:compensation",
    "salary" => "employment:compensation",
    "salaries" => "employment:compensation",
    "paga" => "employment:compensation",
    "pagas" => "employment:compensation",
    "pagamos" => "employment:compensation",
    "pagan" => "employment:compensation",
    "salario" => "employment:compensation",
    "salarios" => "employment:compensation",
    "sueldo" => "employment:compensation",
    "sueldos" => "employment:compensation",
    "paie" => "employment:compensation",
    "paies" => "employment:compensation",
    "payer" => "employment:compensation",
    "salaire" => "employment:compensation",
    "salaires" => "employment:compensation",
    "rémunération" => "employment:compensation",
    "rémunérations" => "employment:compensation"
  }

  # Treat the tightly coupled "star chart" idea as one recall cue across the
  # supported interface languages. Requiring both a celestial term and a map
  # term prevents a note about stars or an unrelated map from matching alone.
  @memory_compound_term_groups %{
    "reference:star-chart" => [
      MapSet.new(~w(
          star stars étoile étoiles estrella estrellas estelar estelares celestial céleste celeste
          constellation constellations constelación constelaciones constelacion
        )),
      MapSet.new(~w(chart charts map maps mapa mapas carte cartes))
    ],
    # Require both the object and concealment cue so a query about keys or
    # hidden objects alone does not retrieve a concealed-key clue.
    "clue:concealed-key" => [
      MapSet.new(~w(key keys llave llaves clé clés clef clefs)),
      MapSet.new(~w(
          hid hide hides hidden hiding conceal concealed conceals concealing
          escondido escondida escondidos escondidas esconder escondió escondieron escondimos
          oculto oculta ocultos ocultas ocultar ocultó ocultaron ocultamos
          caché cachée cachés cachées cacher cachons dissimulé dissimulée dissimulés
          dissimulées dissimuler dissimule
        ))
    ]
  }
  @memory_compound_concepts MapSet.new(Map.keys(@memory_compound_term_groups))

  @autumn_terms MapSet.new(["fall", "autumn", "otoño", "automne"])
  @seasonal_supporting_concepts MapSet.new([
                                  "occasion:event",
                                  "occasion:tasting",
                                  "allocation:set-aside"
                                ])
  @event_subconcepts MapSet.new(["occasion:tasting"])
  @typed_commitment_concepts MapSet.new(["campaign:commitment", "campaign:plan"])
  @social_memory_concepts MapSet.new(["campaign:meeting", "campaign:response"])
  @employment_memory_concepts MapSet.new([
                                "employment:work",
                                "employment:acceptance",
                                "employment:compensation",
                                "employment:terms",
                                "campaign:commitment"
                              ])
  @ambiguous_compensation_terms MapSet.new([
                                  "pay",
                                  "pays",
                                  "paid",
                                  "paga",
                                  "pagas",
                                  "pagamos",
                                  "pagan",
                                  "paie",
                                  "paies",
                                  "payer"
                                ])
  @history_broad_action_terms MapSet.new(~w(
    ask asks asked asking request requests requesting
    do does did doing need needs needed needing happen happens happened happening
    see sees seeing look looks looking tell tells telling show shows showing describe describes describing
    close closes closing evening night tonight morning today tomorrow now later next around else anything something
    hacer hace haces hacemos hacen falta necesito necesitas necesitamos necesitan pasando pasa pasar ver mirar
    preguntar pregunto preguntas necesita algo siguiente noche tarde ahora cerrar cerramos qué
    quoi est faire faut besoin demander demande demandes passe passer voir regarder dis dire montre montrer
    prochain prochaine prochainement soir soirée soiree demain maintenant fermer ferme fermons
  ))

  @measured_sections [
    :campaign,
    :world,
    :inventory,
    :places,
    :travel_connections,
    :communication_paths,
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
    communication_paths: :section_communication_paths_bytes,
    objectives: :section_objectives_bytes,
    memory: :section_memory_bytes,
    continuity: :section_continuity_bytes,
    characters: :section_characters_bytes,
    panels: :section_panels_bytes,
    history: :section_history_bytes
  }

  @doc "Returns a compact context and safe size metrics, or a sanitized compilation error."
  def compile(context, instructions, model, opts \\ [])

  def compile(context, instructions, model, opts)
      when is_map(context) and is_binary(instructions) do
    budget = byte_budget(model, opts)
    {context, preferred_history_sequences} = without_context_retrieval_metadata(context)

    {selected_context, continuity_details_omitted?} =
      retrieve_relevant_continuity_details(context)

    {selected_context, inventory_details_omitted?, inventory_items_omitted?} =
      project_relevant_inventory(selected_context)

    completeness =
      %{}
      |> maybe_put(
        :continuity_memory_details_omitted,
        if(continuity_details_omitted?, do: true)
      )
      |> maybe_put(:inventory_details_omitted, if(inventory_details_omitted?, do: true))
      |> maybe_put(:inventory_items_omitted, if(inventory_items_omitted?, do: true))

    selected_context =
      if map_size(completeness) > 0,
        do: context_with_completeness(selected_context, completeness),
        else: selected_context

    retrieval_omissions =
      [
        continuity_memory_details: continuity_details_omitted?,
        inventory_details: inventory_details_omitted?,
        inventory_items: inventory_items_omitted?
      ]
      |> Enum.filter(&elem(&1, 1))
      |> Enum.map(&elem(&1, 0))

    first_pass = compact_context(selected_context, preferred_history_sequences)

    omissions = Enum.uniq(retrieval_omissions ++ first_pass.omissions)

    metrics =
      measure(
        first_pass.context,
        instructions,
        budget,
        omissions != [],
        omissions
      )

    if metrics.estimated_request_bytes <= budget do
      {:ok, %{context: first_pass.context, metrics: metrics}}
    else
      {context, _compacted_omissions, metrics} =
        compact_history_to_budget(
          first_pass.context,
          instructions,
          budget,
          omissions,
          metrics
        )

      if metrics.estimated_request_bytes <= budget do
        {:ok, %{context: context, metrics: metrics}}
      else
        {context, _omissions, metrics} =
          omit_history_to_budget(context, instructions, budget, omissions, metrics)

        if metrics.estimated_request_bytes <= budget do
          {:ok, %{context: context, metrics: metrics}}
        else
          emit_metrics(metrics)
          {:error, {:context_budget_exceeded, budget_diagnostics(metrics)}}
        end
      end
    end
  rescue
    _error -> {:error, :context_compilation_failed}
  end

  def compile(_context, _instructions, _model, _opts),
    do: {:error, :context_compilation_failed}

  @doc "Emits only numeric size/usage data; campaign text and identifiers are never attached."
  def emit_metrics(metrics, provider_usage \\ %{})

  def emit_metrics(metrics, provider_usage) when is_map(metrics) do
    usage = if is_map(provider_usage), do: provider_usage, else: %{}

    measurements =
      metrics
      |> Map.take([
        :budget_bytes,
        :estimated_request_bytes,
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

  defp byte_budget(model, opts) do
    configured = Application.get_env(:storyteller, :gm_context_byte_budgets, %{})

    budget =
      Keyword.get(opts, :context_input_byte_budget) ||
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
      budget_bytes: budget,
      instructions_bytes: instructions_bytes,
      context_json_bytes: context_json_bytes,
      estimated_request_bytes: instructions_bytes + context_json_bytes + @framing_allowance,
      section_bytes: section_bytes,
      compacted?: compacted?,
      omissions: omissions
    }
  end

  defp metric_key(section), do: Map.fetch!(@section_metric_keys, section)

  defp budget_diagnostics(metrics) do
    section_sizes =
      Map.new(@measured_sections, fn section ->
        {Atom.to_string(section), Map.fetch!(metrics.section_bytes, metric_key(section))}
      end)
      |> Map.put("gm_instructions", metrics.instructions_bytes)

    largest_sections =
      section_sizes
      |> Enum.sort_by(fn {section, bytes} -> {-bytes, section} end)
      |> Enum.take(3)
      |> Enum.map(fn {section, bytes} -> %{category: section, bytes: bytes} end)

    %{
      budget_bytes: metrics.budget_bytes,
      estimated_request_bytes: metrics.estimated_request_bytes,
      instructions_bytes: metrics.instructions_bytes,
      context_json_bytes: metrics.context_json_bytes,
      section_bytes: section_sizes,
      largest_sections: largest_sections
    }
  end

  defp compact_context(context, preferred_history_sequences) do
    terms = query_terms(context)
    history_query = history_query(context)
    player_place_id = player_place_id(context)

    {history, history_omitted?} =
      compact_history(
        Map.get(context, "history", context[:history]),
        history_query,
        MapSet.new(preferred_history_sequences)
      )

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

  # If the first relevance pass still leaves an oversized request, shorten
  # narration in progressively smaller steps. Canonical world, character,
  # place, inventory, resource, objective, and continuity records are kept;
  # only event prose is compressed further.
  defp compact_history_to_budget(context, instructions, budget, omissions, metrics) do
    Enum.reduce_while(
      @history_budget_fallback_tiers,
      {context, omissions, metrics},
      fn {recent_count, recent_chars, older_chars},
         {current_context, current_omissions, _current_metrics} ->
        {history, changed?} =
          compact_history_for_budget(
            value(current_context, :history),
            recent_count,
            recent_chars,
            older_chars
          )

        if changed? do
          updated_omissions = Enum.uniq(current_omissions ++ [:history])

          updated_context =
            current_context
            |> put_context_value("history", history)
            |> context_with_completeness(%{history_compacted: true})

          updated_metrics =
            measure(updated_context, instructions, budget, true, updated_omissions)

          if updated_metrics.estimated_request_bytes <= budget do
            {:halt, {updated_context, updated_omissions, updated_metrics}}
          else
            {:cont, {updated_context, updated_omissions, updated_metrics}}
          end
        else
          {:cont, {current_context, current_omissions, metrics}}
        end
      end
    )
  end

  defp compact_history_for_budget(history, recent_count, recent_chars, older_chars)
       when is_list(history) do
    story_events = Enum.filter(history, &conversation_event?/1)

    recent_sequences =
      story_events |> Enum.take(-recent_count) |> MapSet.new(&event_sequence/1)

    compacted =
      Enum.map(history, fn event ->
        if conversation_event?(event) do
          max_text_chars =
            if MapSet.member?(recent_sequences, event_sequence(event)),
              do: recent_chars,
              else: older_chars

          compact_event(event, max_text_chars)
        else
          event
        end
      end)

    {compacted, compacted != history}
  end

  defp compact_history_for_budget(history, _recent_count, _recent_chars, _older_chars),
    do: {history, false}

  # History is useful recall, but it is not the source of truth for current
  # scene state. If even the shortest retained excerpts prevent a request,
  # omit the transcript from this request and rely on the canonical state,
  # continuity, and selected character profiles that remain in context. The
  # event ledger itself is untouched, and the omission is explicit to the GM.
  defp omit_history_to_budget(context, instructions, budget, omissions, metrics) do
    history = value(context, :history)

    if is_list(history) and history != [] do
      updated_context =
        context
        |> put_context_value("history", [])
        |> context_with_completeness(%{history_compacted: true, history_omitted: true})

      updated_omissions = Enum.uniq(omissions ++ [:history])
      updated_metrics = measure(updated_context, instructions, budget, true, updated_omissions)

      {updated_context, updated_omissions, updated_metrics}
    else
      {context, omissions, metrics}
    end
  end

  # Durable continuity entries remain complete in storage and on the campaign
  # board. Send detail only for a bounded, relevant set from each visibility
  # scope; stable identity/status metadata tells the GM that other records
  # exist without spending every turn's context on their full text.
  defp retrieve_relevant_continuity_details(context) do
    continuity = value(context, :continuity)

    if is_map(continuity) do
      terms = query_terms(context)

      {selected, omitted?} =
        Enum.map_reduce(continuity, false, fn {visibility, entries}, any_omitted? ->
          entries = if is_list(entries), do: entries, else: []

          detailed_entry_ids =
            entries
            |> Enum.filter(&memory_relevant?(&1, terms))
            |> Enum.take(-@max_continuity_memory_details)
            |> MapSet.new(&value(&1, :entry_id))

          {selected_entries, omitted_here?} =
            Enum.map_reduce(entries, false, fn entry, omitted_details? ->
              relevant? = MapSet.member?(detailed_entry_ids, value(entry, :entry_id))

              if relevant? or not is_map(entry) do
                {entry, omitted_details?}
              else
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
              end
            end)

          {{visibility, selected_entries}, any_omitted? or omitted_here?}
        end)
        |> then(fn {groups, any_omitted?} -> {Map.new(groups), any_omitted?} end)

      {put_context_value(context, "continuity", selected), omitted?}
    else
      {context, false}
    end
  end

  # Keep every item identity and quantity for small inventories. For larger
  # ledgers, send the items that best match the current turn plus a small recent
  # slice. Send bounded descriptions/properties only for the strongest matches.
  # The complete inventory remains canonical in the database and is still used
  # when validating any proposed item operation.
  defp project_relevant_inventory(context) do
    inventory = value(context, :inventory)

    if is_map(inventory) do
      terms = query_terms(context)

      {selected, {details_omitted?, items_omitted?}} =
        Enum.map_reduce(inventory, {false, false}, fn {visibility, items},
                                                      {any_details_omitted?, any_items_omitted?} ->
          if is_list(items) do
            {rows, details_omitted_here?, items_omitted_here?} =
              project_inventory_items(items, terms)

            {{visibility, rows},
             {any_details_omitted? or details_omitted_here?,
              any_items_omitted? or items_omitted_here?}}
          else
            {{visibility, items}, {any_details_omitted?, any_items_omitted?}}
          end
        end)
        |> then(fn {groups, omissions} -> {Map.new(groups), omissions} end)

      {put_context_value(context, "inventory", selected), details_omitted?, items_omitted?}
    else
      {context, false, false}
    end
  end

  defp project_inventory_items(items, terms) do
    scored_items =
      Enum.map(items, fn item ->
        relevance_score = relevance_score(inventory_detail_text(item), terms)
        {item, relevance_score}
      end)

    selected_indexes = selected_inventory_indexes(scored_items)

    detailed_indexes =
      if length(items) <= @max_inventory_detail_count do
        selected_indexes
      else
        scored_items
        |> Enum.with_index()
        |> Enum.filter(fn {{_item, score}, index} ->
          score > 0 and MapSet.member?(selected_indexes, index)
        end)
        |> Enum.sort_by(fn {{_item, score}, index} -> {-score, -index} end)
        |> Enum.take(@max_inventory_detail_count)
        |> Enum.map(&elem(&1, 1))
        |> MapSet.new()
      end

    {rows, {details_omitted?, items_omitted?}} =
      items
      |> Enum.with_index()
      |> Enum.reduce({[], false, false}, fn {item, index},
                                            {acc, any_details_omitted?, any_items_omitted?} ->
        cond do
          not MapSet.member?(selected_indexes, index) ->
            {acc, any_details_omitted?, true}

          MapSet.member?(detailed_indexes, index) ->
            {compacted_item, details_omitted_here?} = compact_selected_inventory_item(item)

            {acc ++ [compacted_item], any_details_omitted? or details_omitted_here?,
             any_items_omitted?}

          true ->
            compacted_item = compact_inventory_item(item)

            {acc ++ [compacted_item], any_details_omitted? or compacted_item != item,
             any_items_omitted?}
        end
      end)
      |> then(fn {rows, details_omitted?, items_omitted?} ->
        {rows, {details_omitted?, items_omitted?}}
      end)

    {rows, details_omitted?, items_omitted?}
  end

  defp selected_inventory_indexes([]), do: MapSet.new()

  defp selected_inventory_indexes(scored_items)
       when length(scored_items) <= @max_inventory_context_items do
    0..(length(scored_items) - 1) |> MapSet.new()
  end

  defp selected_inventory_indexes(scored_items) do
    relevant_indexes =
      scored_items
      |> Enum.with_index()
      |> Enum.filter(fn {{_item, score}, _index} -> score > 0 end)
      |> Enum.sort_by(fn {{_item, score}, index} -> {-score, -index} end)
      |> Enum.take(@max_relevant_inventory_items)
      |> Enum.map(&elem(&1, 1))

    recent_start = max(length(scored_items) - @recent_inventory_context_items, 0)
    recent_indexes = Enum.to_list(recent_start..(length(scored_items) - 1))

    MapSet.new(relevant_indexes ++ recent_indexes)
  end

  defp inventory_detail_text(item) when is_map(item) do
    properties = value(item, :properties)

    property_text =
      if is_map(properties) or is_list(properties), do: Jason.encode!(properties), else: ""

    [
      value(item, :name),
      value(item, :description),
      value(item, :category),
      value(item, :unit),
      property_text
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp inventory_detail_text(_item), do: ""

  defp compact_inventory_item(item) when is_map(item),
    do: Map.drop(item, [:description, "description", :properties, "properties"])

  defp compact_inventory_item(item), do: item

  defp compact_selected_inventory_item(item) when is_map(item) do
    description = value(item, :description)
    properties = value(item, :properties)

    compacted_description = compact_text(description, @max_inventory_description_chars)

    {compacted_item, description_omitted?} =
      if compacted_description != description do
        {put_context_value(item, "description", compacted_description), true}
      else
        {item, false}
      end

    properties_json =
      if is_map(properties) or is_list(properties), do: Jason.encode!(properties), else: ""

    if byte_size(properties_json) > @max_inventory_properties_bytes do
      {Map.drop(compacted_item, [:properties, "properties"]), true}
    else
      {compacted_item, description_omitted?}
    end
  end

  defp compact_selected_inventory_item(item), do: {item, false}

  defp memory_relevant?(entry, query_terms) do
    note_text = entry_text(entry)
    note_terms = meaningful_terms(note_text)
    typed_commitment? = value(entry, :kind) in ["commitment", :commitment]

    meaningful_query_terms =
      normalize_memory_terms(query_terms)
      |> MapSet.difference(@memory_stopwords)

    matched_concepts = MapSet.intersection(meaningful_query_terms, note_terms)

    other_matched_concepts =
      matched_concepts
      |> MapSet.difference(@employment_memory_concepts)
      |> MapSet.difference(@typed_commitment_concepts)
      |> MapSet.difference(@social_memory_concepts)

    employment_matches = MapSet.intersection(matched_concepts, @employment_memory_concepts)

    raw_query_terms = MapSet.new(query_terms)

    employment_work_or_acceptance? =
      MapSet.member?(employment_matches, "employment:work") or
        MapSet.member?(employment_matches, "employment:acceptance")

    employment_relevant? =
      (MapSet.member?(employment_matches, "employment:compensation") and
         (MapSet.disjoint?(raw_query_terms, @ambiguous_compensation_terms) or
            employment_work_or_acceptance?)) or
        (MapSet.member?(employment_matches, "employment:work") and
           MapSet.member?(employment_matches, "employment:acceptance")) or
        employment_terms_relevant?(employment_matches) or
        employment_commitment_relevant?(employment_matches)

    query_support = MapSet.intersection(meaningful_query_terms, @seasonal_supporting_concepts)
    note_support = MapSet.intersection(note_terms, @seasonal_supporting_concepts)

    exact_season_match? =
      not MapSet.disjoint?(
        MapSet.intersection(query_terms, @autumn_terms),
        MapSet.intersection(raw_meaningful_terms(note_text), @autumn_terms)
      )

    cond do
      # A "what's next?" prompt asks for active obligations. Do not let a
      # shared topic word pull in an ordinary object/place fact or a closed
      # commitment just because it appears in the same scene.
      MapSet.member?(meaningful_query_terms, "campaign:next-step") ->
        typed_commitment? and value(entry, :status) in ["active", :active]

      not MapSet.disjoint?(meaningful_query_terms, @memory_compound_concepts) ->
        not MapSet.disjoint?(note_terms, @memory_compound_concepts)

      social_commitment_relevant?(entry, matched_concepts) ->
        true

      typed_commitment_relevant?(entry, meaningful_query_terms) ->
        true

      employment_relevant? ->
        true

      MapSet.size(other_matched_concepts) == 0 ->
        false

      MapSet.member?(other_matched_concepts, "season:autumn") ->
        if MapSet.size(query_support) == 0 do
          exact_season_match?
        else
          seasonal_support_matches?(query_support, note_support)
        end

      true ->
        true
    end
  end

  # A bounded meeting/reply cue can recover an older social commitment even
  # when the query is phrased in another supported language. Require a typed
  # commitment so matching mentions in ordinary facts do not broaden retrieval.
  defp social_commitment_relevant?(entry, matched_concepts) do
    value(entry, :kind) in ["commitment", :commitment] and
      not MapSet.disjoint?(matched_concepts, @social_memory_concepts)
  end

  # Generic plan/intent or promise/decision cues can refer to a typed campaign
  # commitment even when the query and note share no subject words. For plan
  # queries, recall only active commitments; ordinary facts and completed
  # commitments cannot qualify from the generic cue alone.
  defp typed_commitment_relevant?(entry, query_terms) do
    typed_commitment? = value(entry, :kind) in ["commitment", :commitment]

    cond do
      not typed_commitment? ->
        false

      MapSet.member?(query_terms, "campaign:plan") ->
        value(entry, :status) in ["active", :active]

      true ->
        MapSet.member?(query_terms, "campaign:commitment")
    end
  end

  # Terms/schedule questions and a character's promise can refer to an older
  # job offer without repeating the note's original wording. Require an
  # employment-domain cue on both sides of each relation so generic bridge
  # hours, toll payments, and unrelated promises do not pull in job memories.
  defp employment_terms_relevant?(employment_matches) do
    MapSet.member?(employment_matches, "employment:terms") and
      (MapSet.member?(employment_matches, "employment:work") or
         MapSet.member?(employment_matches, "employment:acceptance"))
  end

  defp employment_commitment_relevant?(employment_matches) do
    MapSet.member?(employment_matches, "campaign:commitment") and
      MapSet.member?(employment_matches, "employment:work")
  end

  # A broad "fall event" query should retrieve distinct event candidates. A
  # tasting is an event subtype, but a note must still match every narrower
  # requested cue (such as an allocation) to be included in a specific query.
  defp seasonal_support_matches?(query_support, note_support) do
    event_requested? = MapSet.member?(query_support, "occasion:event")
    specific_support = MapSet.delete(query_support, "occasion:event")

    event_matches? =
      MapSet.member?(note_support, "occasion:event") or
        not MapSet.disjoint?(note_support, @event_subconcepts)

    MapSet.subset?(specific_support, note_support) and
      (not event_requested? or event_matches?)
  end

  defp meaningful_terms(text) when is_binary(text) do
    text
    |> raw_meaningful_terms()
    |> normalize_memory_terms()
  end

  defp meaningful_terms(_text), do: MapSet.new()

  defp normalize_memory_terms(terms) do
    normalized_terms = terms |> Enum.map(&memory_term_alias/1) |> MapSet.new()

    Enum.reduce(@memory_compound_term_groups, normalized_terms, fn {concept, groups}, acc ->
      if Enum.all?(groups, &(not MapSet.disjoint?(terms, &1))) do
        MapSet.put(acc, concept)
      else
        acc
      end
    end)
  end

  defp raw_meaningful_terms(text) when is_binary(text) do
    text
    |> String.downcase()
    |> then(&Regex.scan(~r/[\p{L}\p{N}]{3,}/u, &1))
    |> List.flatten()
    |> Enum.reject(&MapSet.member?(@memory_stopwords, &1))
    |> MapSet.new()
  end

  defp raw_meaningful_terms(_text), do: MapSet.new()

  defp memory_term_alias(term), do: Map.get(@memory_term_aliases, term, term)

  defp compact_history(history, terms, preferred_sequences) when is_list(history) do
    story_events = Enum.filter(history, &conversation_event?/1)
    recent = Enum.take(story_events, -@recent_history_count)
    recent_sequences = MapSet.new(recent, &event_sequence/1)

    older_candidates =
      story_events
      |> Enum.reject(&MapSet.member?(recent_sequences, event_sequence(&1)))
      |> Enum.map(fn event ->
        preferred? = MapSet.member?(preferred_sequences, event_sequence(event))
        {history_relevance_score(event, terms), preferred?, event}
      end)

    has_relevant_retrieved_event? =
      Enum.any?(older_candidates, fn {score, preferred?, _event} -> preferred? and score > 0 end)

    relevant_older =
      older_candidates
      |> Enum.filter(fn {score, preferred?, _event} ->
        score > 0 or (preferred? and not has_relevant_retrieved_event?)
      end)
      |> Enum.sort_by(fn {score, preferred?, event} ->
        {if(score > 0, do: 0, else: 1), if(preferred?, do: 0, else: 1), -score,
         -event_sequence(event)}
      end)
      |> Enum.take(@relevant_history_count)
      |> Enum.map(&elem(&1, 2))

    selected =
      relevant_older
      |> Enum.map(&compact_event(&1, @relevant_event_text_chars))
      |> Kernel.++(Enum.map(recent, &compact_event(&1, @recent_event_text_chars)))
      |> Enum.sort_by(&event_sequence/1)

    omitted? = length(selected) < length(history) or selected != history
    {selected, omitted?}
  end

  defp compact_history(history, _terms, _preferred_sequences), do: {history, false}

  defp conversation_event?(event) when is_map(event) do
    type = Map.get(event, "event_type", Map.get(event, :event_type))
    type = if is_atom(type), do: Atom.to_string(type), else: type

    type in ~w(player_action player_question time_passage gm_narration npc_dialogue remote_message character_activity roll_request player_roll)
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
          "path_id",
          "channel",
          :text,
          :test,
          :difficulty,
          :target,
          :result,
          :die,
          :path_id,
          :channel
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

        mentioned? =
          name_mentioned?(value(character, :name), terms) or
            character_facts_relevant?(character, terms)

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
              "active_duty",
              :speaker_id,
              :name,
              :role,
              :current_place_id,
              :active_duty
            ])
            |> maybe_put_context("current_place", compact_place_identity(current_place))
            |> maybe_put_context(
              "visible_facts",
              small_remote_public_facts(value(character, :visible_facts))
            )

          {compact, true}
        end
      end)

    {compacted, omitted?}
  end

  defp compact_characters(characters, _terms, _player_place_id), do: {characters, false}

  defp small_remote_public_facts(facts) when is_map(facts) do
    if byte_size(Jason.encode!(facts)) <= 256, do: facts
  end

  defp small_remote_public_facts(_facts), do: nil

  defp character_facts_relevant?(character, terms) do
    [value(character, :visible_facts), value(character, :gm_private_facts)]
    |> Enum.filter(&is_map/1)
    |> Enum.any?(fn facts -> relevance_score(Jason.encode!(facts), terms) > 0 end)
  end

  defp compact_places(places, terms, player_place_id, context) when is_map(places) do
    edges = Map.get(context, "travel_connections", context[:travel_connections]) || %{}

    adjacent_ids =
      edges
      |> all_edges()
      |> Enum.flat_map(fn edge -> [value(edge, :place_a_id), value(edge, :place_b_id)] end)
      |> MapSet.new()

    relevant_character_place_ids =
      context
      |> value(:characters)
      |> List.wrap()
      |> Enum.filter(fn character ->
        speaker_id = value(character, :speaker_id)

        speaker_id == "player" or value(character, :current_place_id) == player_place_id or
          name_mentioned?(value(character, :name), terms) or
          character_facts_relevant?(character, terms)
      end)
      |> Enum.map(&value(&1, :current_place_id))
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    {result, omitted?} =
      Enum.map_reduce(places, false, fn {visibility, place_rows}, any_omitted?
                                        when is_list(place_rows) ->
        {rows, omitted_here?} =
          Enum.map_reduce(place_rows, false, fn place, omitted_details? ->
            place_id = value(place, :place_id)

            relevant? =
              place_id == player_place_id or MapSet.member?(adjacent_ids, place_id) or
                MapSet.member?(relevant_character_place_ids, place_id) or
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

          # The campaign database keeps the complete ledger. Before size
          # compaction, relevant continuity details have already been selected
          # under a separate cap; preserve those active details. Closed entries
          # outside the recent window can safely lose detail while their stable
          # identity/status metadata remains available.
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
    terms = query_components(context) |> Map.fetch!(:terms)

    if remaining_task_query?(value(context, :player_action)) do
      MapSet.put(terms, "campaign:next-step")
    else
      terms
    end
  end

  # Recognize a narrow "what remains to do" phrasing in each supported
  # language. Requiring both a remaining-work word and an action verb avoids
  # treating inventory questions such as "what wine remains?" as a request
  # for every active commitment.
  defp remaining_task_query?(action) when is_binary(action) do
    terms =
      action
      |> String.downcase()
      |> then(&Regex.scan(~r/[\p{L}\p{N}]{2,}/u, &1))
      |> List.flatten()

    ordered_term_pair?(terms, ~w(left remain remains remaining), ~w(do doing)) or
      ordered_term_pair?(terms, ~w(queda quedan quedamos), ~w(hacer)) or
      ordered_term_pair?(terms, ~w(reste restent), ~w(faire accomplir))
  end

  defp remaining_task_query?(_action), do: false

  defp ordered_term_pair?(terms, first_terms, later_terms) do
    terms
    |> Enum.with_index()
    |> Enum.any?(fn {term, index} ->
      later_term? =
        terms
        |> Enum.slice(index + 1, 5)
        |> Enum.any?(&(&1 in later_terms))

      term in first_terms and later_term?
    end)
  end

  defp history_query(context), do: query_components(context)

  defp query_components(context) do
    action = value(context, :player_action) || ""
    player_place_id = player_place_id(context)

    scene_characters =
      context
      |> value(:characters)
      |> List.wrap()
      |> Enum.filter(fn character ->
        value(character, :speaker_id) == "player" or
          (is_binary(player_place_id) and value(character, :current_place_id) == player_place_id)
      end)
      |> Enum.sort_by(&value(&1, :speaker_id))
      |> Enum.take(@max_history_scene_speakers)

    scene_text =
      scene_characters
      |> Enum.map(&value(&1, :name))
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")

    connected_place_ids = connected_place_ids(context, player_place_id)
    relevant_place_ids = MapSet.new([player_place_id | connected_place_ids])

    place_text =
      context
      |> value(:places)
      |> case do
        map when is_map(map) -> Map.values(map) |> List.flatten()
        _ -> []
      end
      |> Enum.filter(&MapSet.member?(relevant_place_ids, value(&1, :place_id)))
      |> Enum.map(&value(&1, :name))
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")

    action_terms = raw_meaningful_terms(action)
    action_specific_terms = MapSet.difference(action_terms, @history_broad_action_terms)
    place_and_character_terms = raw_meaningful_terms([scene_text, place_text] |> Enum.join(" "))

    focused_character_terms =
      focused_off_scene_character_terms(context, player_place_id, action_terms)

    speaker_terms =
      scene_characters
      |> Enum.reject(&(value(&1, :speaker_id) == "player"))
      |> Enum.map(&value(&1, :speaker_id))
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.downcase/1)
      |> MapSet.new()

    anchor_terms = MapSet.union(place_and_character_terms, speaker_terms)

    %{
      terms: MapSet.union(action_terms, anchor_terms),
      action_terms: MapSet.difference(action_specific_terms, anchor_terms),
      anchor_terms: anchor_terms,
      focused_character_terms: focused_character_terms
    }
  end

  defp focused_off_scene_character_terms(_context, player_place_id, _action_terms)
       when not is_binary(player_place_id),
       do: MapSet.new()

  defp focused_off_scene_character_terms(context, player_place_id, action_terms) do
    context
    |> value(:characters)
    |> List.wrap()
    |> Enum.reduce(MapSet.new(), fn character, terms ->
      current_place_id = value(character, :current_place_id)
      name_terms = raw_meaningful_terms(value(character, :name))

      mentioned_name_terms = MapSet.intersection(name_terms, action_terms)

      if value(character, :speaker_id) != "player" and is_binary(current_place_id) and
           current_place_id != player_place_id and MapSet.size(mentioned_name_terms) > 0 do
        speaker_id = value(character, :speaker_id)

        terms
        |> MapSet.union(mentioned_name_terms)
        |> maybe_put_speaker_id(speaker_id)
      else
        terms
      end
    end)
  end

  defp maybe_put_speaker_id(terms, speaker_id) when is_binary(speaker_id),
    do: MapSet.put(terms, String.downcase(speaker_id))

  defp maybe_put_speaker_id(terms, _speaker_id), do: terms

  defp history_relevance_score(event, %{action_terms: action_terms} = query)
       when is_map(event) do
    text = event_text(event)

    event_terms =
      case value(event, :speaker_id) do
        speaker_id when is_binary(speaker_id) ->
          MapSet.put(raw_meaningful_terms(text), String.downcase(speaker_id))

        _ ->
          raw_meaningful_terms(text)
      end

    focused_character_terms = Map.get(query, :focused_character_terms, MapSet.new())

    focused_character_match? =
      MapSet.size(focused_character_terms) == 0 or
        not MapSet.disjoint?(event_terms, focused_character_terms)

    if not focused_character_match? do
      0
    else
      if MapSet.size(action_terms) < 2 do
        relevance_score(text, query.anchor_terms)
      else
        action_matches = MapSet.intersection(event_terms, action_terms)
        anchor_matches = MapSet.intersection(event_terms, query.anchor_terms)
        action_match_count = MapSet.size(action_matches)
        anchor_match_count = MapSet.size(anchor_matches)

        cond do
          action_match_count >= 2 ->
            action_match_count + anchor_match_count

          action_match_count >= 1 and anchor_match_count >= 1 ->
            action_match_count + anchor_match_count

          true ->
            0
        end
      end
    end
  end

  defp history_relevance_score(event, terms), do: relevance_score(event_text(event), terms)

  defp connected_place_ids(_context, nil), do: []

  defp connected_place_ids(context, player_place_id) do
    edges = context |> value(:travel_connections) |> all_edges()

    edges
    |> Enum.filter(fn edge ->
      value(edge, :place_a_id) == player_place_id or
        value(edge, :place_b_id) == player_place_id
    end)
    |> Enum.sort_by(fn edge ->
      {value(edge, :travel_minutes) || 0, value(edge, :place_a_id), value(edge, :place_b_id)}
    end)
    |> Enum.take(@max_history_connected_places)
    |> Enum.map(fn edge ->
      if value(edge, :place_a_id) == player_place_id,
        do: value(edge, :place_b_id),
        else: value(edge, :place_a_id)
    end)
    |> Enum.uniq()
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

  defp without_context_retrieval_metadata(context) when is_map(context) do
    metadata = value(context, :context_retrieval) || %{}
    sequences = value(metadata, :older_history_sequences)
    sequences = if is_list(sequences), do: Enum.filter(sequences, &is_integer/1), else: []

    context = Map.delete(context, :context_retrieval) |> Map.delete("context_retrieval")
    {context, sequences}
  end

  defp without_context_retrieval_metadata(context), do: {context, []}

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
