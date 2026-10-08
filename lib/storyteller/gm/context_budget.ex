defmodule Storyteller.GM.ContextBudget do
  @moduledoc """
  Builds a deterministic, relevance-ranked GM context using a local serialized-
  byte target to guide compaction. The target is not a request veto or the
  model's context window, an account usage limit, or a token count. The provider
  decides whether the resulting request fits its actual context window; a
  provider rejection triggers the scene-focused recovery path. Successful
  Responses usage is recorded separately when the provider reports it.
  """

  alias Storyteller.GM.RequestEnvelope

  @default_budget 128_000
  @recent_history_count 12
  @relevant_history_count 8
  @max_history_scene_speakers 32
  @max_history_connected_places 24
  @recent_event_text_chars 1_600
  @relevant_event_text_chars 900
  @memory_summary_chars 1_500
  @max_continuity_context_rows 64
  @broad_inventory_terms MapSet.new(~w(
    inventory inventories item items gear equipment supplies stock ledger
    wine wines vino vinos bottle bottles potion potions cash money funds
    resource resources inventoryario inventario artículos articulos objetos
    equipo suministros existencias vino vinos botella botellas poción pociones
    pociones efectivo dinero fondos recurso recursos inventaire articles objets
    équipement equipement fournitures stock vin vins bouteille bouteilles
    potion potions espèces especes argent fonds ressource ressources
  ))
  @max_world_scope_bytes 64_000
  @max_world_value_bytes 1_200
  @max_panel_context_fields 32
  @max_panel_context_bytes 48_000
  @max_panel_value_chars 800
  @max_character_fact_bytes 650
  @max_character_voice_bytes 420
  @max_character_activity_chars 220
  @max_open_objective_rows 24
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

  @doc "Returns a relevance-ranked context and safe size metrics, or a sanitized compilation error."
  def compile(context, instructions, model, opts \\ [])

  def compile(context, instructions, model, opts)
      when is_map(context) and is_binary(instructions) do
    budget = byte_budget(model, opts)
    {context, preferred_history_sequences} = without_context_retrieval_metadata(context)

    compile_compacted_context(
      context,
      instructions,
      model,
      opts,
      budget,
      preferred_history_sequences
    )
  rescue
    _error -> {:error, :context_compilation_failed}
  end

  def compile(_context, _instructions, _model, _opts),
    do: {:error, :context_compilation_failed}

  defp compile_compacted_context(
         context,
         instructions,
         model,
         opts,
         budget,
         preferred_history_sequences
       ) do
    {selected_context, continuity_details_omitted?} =
      retrieve_relevant_continuity_details(context)

    {selected_context, world_fields_omitted?, world_details_compacted?} =
      project_relevant_world_state(selected_context)

    {selected_context, panel_fields_omitted?, panel_values_compacted?} =
      project_relevant_panels(selected_context)

    completeness =
      %{}
      |> maybe_put(
        :continuity_memory_details_omitted,
        if(continuity_details_omitted?, do: true)
      )
      |> maybe_put(:world_state_fields_omitted, if(world_fields_omitted?, do: true))
      |> maybe_put(:world_state_details_compacted, if(world_details_compacted?, do: true))
      |> maybe_put(:panel_fields_omitted, if(panel_fields_omitted?, do: true))
      |> maybe_put(:panel_values_compacted, if(panel_values_compacted?, do: true))

    selected_context =
      if map_size(completeness) > 0,
        do: context_with_completeness(selected_context, completeness),
        else: selected_context

    retrieval_omissions =
      [
        continuity_memory_details: continuity_details_omitted?,
        world_state_fields: world_fields_omitted?,
        world_state_details: world_details_compacted?,
        panel_fields: panel_fields_omitted?,
        panel_values: panel_values_compacted?
      ]
      |> Enum.filter(&elem(&1, 1))
      |> Enum.map(&elem(&1, 0))

    first_pass = compact_context(selected_context, preferred_history_sequences)

    omissions = Enum.uniq(retrieval_omissions ++ first_pass.omissions)

    metrics =
      measure(
        first_pass.context,
        instructions,
        model,
        budget,
        omissions != [],
        omissions
      )

    if metrics.estimated_request_bytes <= budget do
      {:ok, %{context: first_pass.context, metrics: report_budget(metrics, model, opts)}}
    else
      {context, compacted_omissions, metrics} =
        compact_history_to_budget(
          first_pass.context,
          instructions,
          model,
          budget,
          omissions,
          metrics
        )

      if metrics.estimated_request_bytes <= budget do
        {:ok, %{context: context, metrics: report_budget(metrics, model, opts)}}
      else
        {detail_context, _detail_omissions, detail_metrics} =
          compact_nonessential_details_to_budget(
            context,
            instructions,
            model,
            budget,
            compacted_omissions,
            metrics
          )

        if detail_metrics.estimated_request_bytes <= budget do
          {:ok, %{context: detail_context, metrics: report_budget(detail_metrics, model, opts)}}
        else
          # The configured size is a compaction target, not a local model
          # limit. Relevance projection and progressive compaction are useful
          # when they produce a request within target. If they cannot, send the
          # best relevant packet and let the provider report its actual context
          # limit. Never reject a turn or erase all history/canon to satisfy an
          # application-defined byte count.
          emit_metrics(detail_metrics)

          {:ok,
           %{
             context: detail_context,
             metrics: report_budget(detail_metrics, model, opts)
           }}
        end
      end
    end
  end

  @doc """
  Builds a small scene-anchored packet for a request that can retrieve omitted
  campaign canon through the bounded, read-only lookup tool.

  This is a last-resort projection: it keeps the player's action, public scene
  identity, game-time/weather anchors, and present cast while marking all other
  canon unknown. It never modifies the supplied source context.
  """
  def compile_retrieval_packet(context, instructions, model, opts \\ [])

  def compile_retrieval_packet(context, instructions, model, opts)
      when is_map(context) and is_binary(instructions) do
    budget = byte_budget(model, opts)
    packet = retrieval_packet(context)

    metrics =
      measure(
        packet,
        instructions,
        model,
        budget,
        true,
        retrieval_packet_omissions(context)
      )

    over_budget? = metrics.estimated_request_bytes > budget

    {:ok,
     %{
       context: packet,
       metrics: report_budget(metrics, model, opts),
       retrieval_packet?: true,
       over_budget?: over_budget?
     }}
  rescue
    _error -> {:error, :context_compilation_failed}
  end

  def compile_retrieval_packet(_context, _instructions, _model, _opts),
    do: {:error, :context_compilation_failed}

  defp retrieval_packet(context) do
    characters = value(context, :characters) |> List.wrap()
    player = Enum.find(characters, &(value(&1, :speaker_id) == "player"))
    player_place_id = value(player, :current_place_id)
    places = value(context, :places) || %{}

    public_places = places |> value(:public) |> List.wrap()

    current_place =
      Enum.find(public_places, fn place ->
        value(place, :place_id) == player_place_id and
          public_visibility?(value(place, :visibility))
      end)

    current_place =
      if current_place do
        current_place
      else
        place = value(player, :current_place)

        if value(place, :place_id) == player_place_id and
             public_visibility?(value(place, :visibility)),
           do: place,
           else: nil
      end

    scene_is_public? = not is_nil(current_place) and is_binary(player_place_id)

    player_packet = retrieval_character(player, true)

    all_scene_characters =
      if scene_is_public? do
        characters
        |> Enum.reject(&(value(&1, :speaker_id) == "player"))
        |> Enum.filter(&(value(&1, :current_place_id) == player_place_id))
      else
        []
      end

    scene_characters =
      all_scene_characters
      |> prioritize_retrieval_scene_cast(context)
      |> Enum.map(&retrieval_character(&1, false))

    cast = if player_packet, do: [player_packet | scene_characters], else: scene_characters

    world = value(context, :world) || %{}
    public_world = world |> value(:public) |> retrieval_world_anchors()

    public_world =
      if scene_is_public? and is_binary(value(current_place, :name)) do
        Map.put(public_world, "location", value(current_place, :name))
      else
        public_world
      end

    %{
      "phase" => value(context, :phase),
      "campaign" => retrieval_campaign(value(context, :campaign)),
      "player_action" => value(context, :player_action),
      "player_roll" => retrieval_roll(value(context, :player_roll)),
      "interaction_mode" => value(context, :interaction_mode),
      "world" => %{"public" => public_world},
      "elapsed_world_clock" => retrieval_clock(value(context, :elapsed_world_clock)),
      "characters" => cast,
      "places" => %{
        "public" => if(scene_is_public?, do: [retrieval_place(current_place)], else: [])
      },
      "communication_paths" =>
        retrieval_communication_paths(value(context, :communication_paths)),
      "history" => [],
      "inventory" => %{},
      "travel_connections" => %{},
      "objectives" => %{},
      "memory" => %{},
      "continuity" => %{},
      "panels" => [],
      "context_completeness" => %{
        "retrieval_packet" => true,
        "omitted_canon_is_unknown" => true,
        "campaign_details_omitted" => true,
        "world_state_fields_omitted" => true,
        "inventory_items_omitted" => true,
        "inventory_details_omitted" => true,
        "travel_connections_omitted" => true,
        "objectives_omitted" => true,
        "continuity_details_omitted" => true,
        "memory_summary_compacted" => true,
        "history_compacted" => true,
        "history_omitted" => true,
        "remote_character_profiles_omitted" => true,
        "remote_place_details_omitted" => true,
        "panel_fields_omitted" => true,
        "gm_private_canon_omitted" => true,
        "scene_cast_truncated" => length(all_scene_characters) > @max_history_scene_speakers
      }
    }
  end

  # Keep a character the player explicitly addressed in a retrieval fallback,
  # even when an unusually large crowd exceeds the compact scene-cast limit.
  # Preserve recent speakers next, then retain the stable source order.
  defp prioritize_retrieval_scene_cast(characters, context) do
    action_terms = raw_meaningful_terms(value(context, :player_action))
    recent_speakers = recent_history_speaker_ids(value(context, :history))

    characters
    |> Enum.with_index()
    |> Enum.sort_by(fn {character, index} ->
      speaker_id = value(character, :speaker_id)
      mentioned? = name_mentioned?(value(character, :name), action_terms)
      public_detail_match? = retrieval_character_detail_match?(character, action_terms)
      recent? = is_binary(speaker_id) and MapSet.member?(recent_speakers, speaker_id)

      priority =
        cond do
          mentioned? -> 0
          public_detail_match? -> 1
          recent? -> 2
          true -> 3
        end

      {priority, index}
    end)
    |> Enum.take(@max_history_scene_speakers)
    |> Enum.map(&elem(&1, 0))
  end

  defp retrieval_character_detail_match?(character, action_terms) do
    detail_terms =
      [safe_json(value(character, :visible_facts)), value(character, :visible_activity)]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")
      |> raw_meaningful_terms()

    MapSet.size(action_terms) > 0 and MapSet.size(detail_terms) > 0 and
      not MapSet.disjoint?(action_terms, detail_terms)
  end

  defp retrieval_packet_omissions(_context),
    do: [
      :retrieval_packet,
      :campaign_details,
      :world_state_fields,
      :inventory_items,
      :inventory_details,
      :travel_connections,
      :objectives,
      :continuity_details,
      :memory_summary,
      :history,
      :remote_character_profiles,
      :remote_place_details,
      :panel_fields,
      :gm_private_canon
    ]

  defp retrieval_character(nil, _player?), do: nil

  defp retrieval_character(character, player?) when is_map(character) do
    fields = ["speaker_id", "name", "role", "first_story_appearance", "current_place_id"]

    character
    |> string_key_subset(fields)
    |> compact_retrieval_fields(["name"])
    |> maybe_add_retrieval_field(
      "visible_activity",
      compact_anchor_text(value(character, :visible_activity), 180)
    )
    |> maybe_add_retrieval_field(
      "voice_guidance",
      retrieval_voice(value(character, :voice_guidance))
    )
    |> Map.put("presence", if(player?, do: "player", else: "present"))
  end

  defp retrieval_character(_character, _player?), do: nil

  defp retrieval_place(place) when is_map(place) do
    place
    |> string_key_subset(["place_id", "name", "visibility"])
    |> compact_retrieval_fields(["name"])
    |> Map.put_new("visibility", "public")
  end

  defp retrieval_place(_place), do: %{}

  defp retrieval_campaign(campaign) when is_map(campaign) do
    campaign
    |> string_key_subset(["title", "narration_language", "genre"])
    |> compact_retrieval_fields(["title", "narration_language", "genre"])
    |> maybe_add_retrieval_field("premise", compact_anchor_text(value(campaign, :premise), 320))
    |> maybe_add_retrieval_field("setting", compact_anchor_text(value(campaign, :setting), 160))
    |> maybe_add_retrieval_field("tone", compact_anchor_text(value(campaign, :tone), 160))
  end

  defp retrieval_campaign(_campaign), do: %{}

  defp retrieval_roll(roll) when is_map(roll),
    do: string_key_subset(roll, ["die", "result", "authorized_by"])

  defp retrieval_roll(_roll), do: nil

  defp retrieval_clock(clock) when is_map(clock) do
    clock
    |> string_key_subset(["total_minutes", "anchor_minutes", "minutes_since_anchor"])
    |> maybe_add_retrieval_field("anchor", compact_anchor_value(value(clock, :anchor), 240))
  end

  defp retrieval_clock(_clock), do: %{}

  defp retrieval_world_anchors(scope) when is_map(scope) do
    scope
    |> Enum.reduce(%{}, fn {key, item}, acc ->
      normalized = key |> to_string() |> String.downcase()

      if normalized in ~w(location date time weather) do
        Map.put(acc, to_string(key), compact_anchor_value(item, 240))
      else
        acc
      end
    end)
  end

  defp retrieval_world_anchors(_scope), do: %{}

  defp retrieval_communication_paths(paths) when is_list(paths),
    do:
      Enum.take(paths, 8)
      |> Enum.map(
        &string_key_subset(&1, ["path_id", "sender_id", "recipient_id", "channel", "endpoint"])
      )

  defp retrieval_communication_paths(_paths), do: %{}

  defp retrieval_voice(voice) when is_map(voice) do
    voice
    |> Enum.take(5)
    |> Enum.reduce(%{}, fn {key, item}, acc ->
      case compact_anchor_text(item, 100) do
        nil -> acc
        value -> Map.put(acc, to_string(key), value)
      end
    end)
  end

  defp retrieval_voice(_voice), do: nil

  defp string_key_subset(map, keys) when is_map(map) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case field_by_name(map, key) do
        nil -> acc
        item -> Map.put(acc, key, item)
      end
    end)
  end

  defp string_key_subset(_map, _keys), do: %{}

  defp field_by_name(map, key) do
    case Map.fetch(map, key) do
      {:ok, item} ->
        item

      :error ->
        Enum.find_value(map, fn {map_key, item} ->
          if to_string(map_key) == key, do: {:found, item}
        end)
        |> unwrap_found()
    end
  end

  defp unwrap_found({:found, item}), do: item
  defp unwrap_found(nil), do: nil

  defp compact_retrieval_fields(map, keys) do
    Enum.reduce(keys, map, fn key, acc ->
      case Map.get(acc, key) do
        value when is_binary(value) ->
          Map.put(acc, key, String.slice(value, 0, 160))

        _ ->
          acc
      end
    end)
  end

  defp maybe_add_retrieval_field(map, _key, nil), do: map
  defp maybe_add_retrieval_field(map, key, value), do: Map.put(map, key, value)

  defp compact_anchor_text(value, max_chars) when is_binary(value) do
    value
    |> String.trim()
    |> String.slice(0, max_chars)
    |> then(fn text -> if text == "", do: nil, else: text end)
  end

  defp compact_anchor_text(_value, _max_chars), do: nil

  defp compact_anchor_value(value, max_chars) when is_binary(value),
    do: compact_anchor_text(value, max_chars)

  defp compact_anchor_value(value, max_chars) when is_map(value) do
    value
    |> Enum.take(12)
    |> Enum.reduce(%{}, fn {key, item}, acc ->
      compacted = compact_anchor_value(item, max_chars)
      if is_nil(compacted), do: acc, else: Map.put(acc, to_string(key), compacted)
    end)
  end

  defp compact_anchor_value(value, max_chars) when is_list(value),
    do: Enum.take(value, 8) |> Enum.map(&compact_anchor_value(&1, max_chars))

  defp compact_anchor_value(value, _max_chars) when is_number(value) or is_boolean(value),
    do: value

  defp compact_anchor_value(_value, _max_chars), do: nil

  defp public_visibility?(visibility), do: visibility in [:public, "public"]

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

  @doc "Returns the local serialized-request compaction target, not a provider context limit."
  def compaction_target_bytes(model, opts \\ []) do
    configured = Application.get_env(:storyteller, :gm_context_byte_budgets, %{})

    limit =
      Keyword.get(opts, :context_input_byte_budget) ||
        Map.get(configured, model, Map.get(configured, "default", @default_budget))

    if is_integer(limit) and limit > 0, do: limit, else: 0
  end

  defp byte_budget(model, opts) do
    budget =
      compaction_target_bytes(model, opts) - max(Keyword.get(opts, :reserve_request_bytes, 0), 0)

    if is_integer(budget) and budget > 0, do: budget, else: 0
  end

  defp report_budget(metrics, model, opts),
    do: Map.put(metrics, :budget_bytes, compaction_target_bytes(model, opts))

  defp measure(context, instructions, model, budget, compacted?, omissions) do
    context_json = Jason.encode!(context)
    input = [user_context_input(context_json)]

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
      estimated_request_bytes: RequestEnvelope.encoded_size(model, instructions, input),
      section_bytes: section_bytes,
      compacted?: compacted?,
      omissions: omissions
    }
  end

  defp user_context_input(context_json) do
    %{
      role: "user",
      content: context_json
    }
  end

  defp metric_key(section), do: Map.fetch!(@section_metric_keys, section)

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

    {characters, profiles_omitted?, character_details_compacted?, characters_omitted?} =
      compact_characters(
        Map.get(context, "characters", context[:characters]),
        terms,
        player_place_id,
        context
      )

    {places, place_details_omitted?, place_details_compacted?, places_omitted?} =
      compact_places(
        Map.get(context, "places", context[:places]),
        terms,
        player_place_id,
        context
      )

    {continuity, continuity_details_omitted?} =
      compact_continuity(Map.get(context, "continuity", context[:continuity]), terms)

    {objectives, objective_rows_omitted?, objective_details_omitted?,
     closed_objective_details_omitted?} =
      compact_objectives(Map.get(context, "objectives", context[:objectives]), terms)

    {memory, memory_omitted?} = compact_memory(Map.get(context, "memory", context[:memory]))

    omissions =
      [
        history: history_omitted?,
        remote_character_profiles: profiles_omitted?,
        character_details: character_details_compacted?,
        characters: characters_omitted?,
        places: places_omitted?,
        remote_place_details: place_details_omitted?,
        place_details: place_details_compacted?,
        continuity_details: continuity_details_omitted?,
        objectives: objective_rows_omitted?,
        objective_details: objective_details_omitted?,
        closed_objective_details: closed_objective_details_omitted?,
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
        character_details_compacted: character_details_compacted?,
        characters_omitted: characters_omitted?,
        places_omitted: places_omitted?,
        remote_place_details_omitted: place_details_omitted?,
        place_details_compacted: place_details_compacted?,
        continuity_details_omitted: continuity_details_omitted?,
        objectives_omitted: objective_rows_omitted?,
        objective_details_omitted: objective_details_omitted?,
        closed_objective_details_omitted: closed_objective_details_omitted?,
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
  defp compact_history_to_budget(context, instructions, model, budget, omissions, metrics) do
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
            measure(updated_context, instructions, model, budget, true, updated_omissions)

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

  # If progressive history compaction still misses the target, trim irrelevant
  # reference prose. Preserve the details matched to this turn and the current
  # scene; the configured byte target is guidance, not a reason to discard
  # useful context or stop the player's action.
  defp compact_nonessential_details_to_budget(
         context,
         instructions,
         model,
         budget,
         omissions,
         _metrics
       ) do
    terms = query_terms(context)

    specified_compaction =
      context
      |> compact_campaign_details_for_budget()
      |> compact_inventory_details_for_budget(terms)
      |> compact_world_details_for_budget(terms)
      |> compact_continuity_details_for_budget(terms)
      |> compact_place_details_for_budget(terms)
      |> compact_character_details_for_budget(terms)
      |> compact_panel_values_for_budget(terms)

    fallback_context = specified_compaction

    changed = %{
      campaign_details_compacted: value(context, :campaign) != value(fallback_context, :campaign),
      inventory_details_omitted:
        value(context, :inventory) != value(fallback_context, :inventory),
      continuity_memory_details_omitted:
        value(context, :continuity) != value(fallback_context, :continuity),
      world_state_details_compacted: value(context, :world) != value(fallback_context, :world),
      place_details_compacted: value(context, :places) != value(fallback_context, :places),
      character_details_compacted:
        value(context, :characters) != value(fallback_context, :characters),
      panel_values_compacted: value(context, :panels) != value(fallback_context, :panels)
    }

    new_omissions =
      changed
      |> Enum.filter(&elem(&1, 1))
      |> Enum.map(fn {key, _} -> omission_for_completeness(key) end)
      |> then(&Enum.uniq(omissions ++ &1))

    fallback_context =
      context_with_completeness(fallback_context, Map.filter(changed, &elem(&1, 1)))

    updated_metrics =
      measure(fallback_context, instructions, model, budget, true, new_omissions)

    {fallback_context, new_omissions, updated_metrics}
  end

  defp omission_for_completeness(:campaign_details_compacted), do: :campaign_details

  defp omission_for_completeness(:inventory_details_omitted), do: :inventory_details

  defp omission_for_completeness(:continuity_memory_details_omitted),
    do: :continuity_memory_details

  defp omission_for_completeness(:world_state_details_compacted), do: :world_state_details
  defp omission_for_completeness(:place_details_compacted), do: :place_details
  defp omission_for_completeness(:character_details_compacted), do: :character_details
  defp omission_for_completeness(:panel_values_compacted), do: :panel_values

  defp compact_campaign_details_for_budget(context) do
    campaign = value(context, :campaign)

    if is_map(campaign) do
      projected =
        Enum.reduce([:title, :premise, :setting, :tone], campaign, fn key, acc ->
          field = value(acc, key)

          max_chars =
            case key do
              :title -> 160
              :premise -> 2_400
              _ -> 280
            end

          if is_binary(field) and String.length(field) > max_chars do
            put_context_value(acc, Atom.to_string(key), compact_text(field, max_chars))
          else
            acc
          end
        end)

      put_context_value(context, "campaign", projected)
    else
      context
    end
  end

  defp compact_world_details_for_budget(context, terms) do
    world = value(context, :world)

    if is_map(world) do
      compacted =
        Map.new(world, fn {visibility, scope} ->
          {visibility, compact_world_scope_for_budget(scope, terms)}
        end)

      put_context_value(context, "world", compacted)
    else
      context
    end
  end

  defp compact_world_scope_for_budget(scope, terms) when is_map(scope) do
    Map.new(scope, fn {key, field} ->
      key_name = to_string(key)
      canonical_anchor? = key_name in ~w(date current_date time current_time weather location)
      field_relevant? = relevance_score(safe_json(%{key => field}), terms) > 0

      compacted =
        if canonical_anchor? or field_relevant? do
          field
        else
          compact_world_field(field, terms)
        end

      {key, compacted}
    end)
  end

  defp compact_world_scope_for_budget(scope, _terms), do: scope

  defp compact_world_field(field, _terms) when is_binary(field) do
    if String.length(field) > @max_world_value_bytes,
      do: compact_text(field, @max_world_value_bytes),
      else: field
  end

  defp compact_world_field(field, terms) when is_map(field) or is_list(field) do
    {compacted, _changed?} = compact_json_value(field, terms, @max_world_value_bytes)
    compacted
  end

  defp compact_world_field(field, _terms), do: field

  defp compact_continuity_details_for_budget(context, terms) do
    continuity = value(context, :continuity)

    if is_map(continuity) do
      projected =
        Map.new(continuity, fn {visibility, entries} ->
          {visibility,
           if(is_list(entries),
             do: Enum.map(entries, &compact_continuity_entry_for_budget(&1, terms)),
             else: entries
           )}
        end)

      put_context_value(context, "continuity", projected)
    else
      context
    end
  end

  defp compact_continuity_entry_for_budget(entry, terms) when is_map(entry) do
    details = value(entry, :details)
    relevant? = memory_relevant?(entry, terms) or relevance_score(entry_text(entry), terms) > 0

    if not relevant? and is_binary(details) and String.length(details) > 280 do
      put_context_value(entry, "details", compact_text(details, 280))
    else
      entry
    end
  end

  defp compact_continuity_entry_for_budget(entry, _terms), do: entry

  defp compact_place_details_for_budget(context, _terms) do
    places = value(context, :places)
    current_place_id = player_place_id(context)
    adjacent_place_ids = MapSet.new(connected_place_ids(context, current_place_id))
    action = value(context, :player_action) || ""
    action_terms = raw_meaningful_terms(action)

    if is_map(places) do
      projected =
        Map.new(places, fn {visibility, rows} ->
          {visibility,
           if(
             is_list(rows),
             do:
               Enum.map(rows, fn place ->
                 preserve_details? =
                   value(place, :place_id) == current_place_id or
                     MapSet.member?(adjacent_place_ids, value(place, :place_id)) or
                     name_explicitly_mentioned?(value(place, :name), action) or
                     relevance_score(safe_json(place), action_terms) >= 2

                 compact_place_for_budget(place, preserve_details?)
               end),
             else: rows
           )}
        end)

      put_context_value(context, "places", projected)
    else
      context
    end
  end

  defp compact_place_for_budget(place, preserve_details?) when is_map(place) do
    description = value(place, :description)
    facts = value(place, :facts)

    place =
      if not preserve_details? and is_binary(description) and String.length(description) > 900 do
        put_context_value(place, "description", compact_text(description, 900))
      else
        place
      end

    {facts, _compacted?} =
      if preserve_details?, do: {facts, false}, else: compact_json_value(facts, MapSet.new(), 700)

    if is_nil(facts), do: place, else: put_context_value(place, "facts", facts)
  end

  defp compact_place_for_budget(place, _preserve_details?), do: place

  defp compact_character_details_for_budget(context, _terms) do
    characters = value(context, :characters)

    if is_list(characters) do
      current_place_id = player_place_id(context)
      recent_speakers = recent_history_speaker_ids(value(context, :history))
      action = value(context, :player_action) || ""
      action_terms = raw_meaningful_terms(action)

      projected =
        Enum.map(characters, fn character ->
          preserve_profile? =
            value(character, :speaker_id) == "player" or
              value(character, :current_place_id) == current_place_id or
              MapSet.member?(recent_speakers, value(character, :speaker_id)) or
              name_explicitly_mentioned?(value(character, :name), action) or
              character_facts_relevant?(character, action_terms)

          character
          |> compact_character_field_for_budget(:visible_facts, 320, action_terms)
          |> compact_character_field_for_budget(:gm_private_facts, 320, action_terms)
          |> maybe_compact_character_voice(preserve_profile?, action_terms)
          |> compact_character_activity_for_budget(action_terms)
        end)

      put_context_value(context, "characters", projected)
    else
      context
    end
  end

  defp compact_character_field_for_budget(character, key, max_bytes, terms)
       when is_map(character) do
    details = value(character, key)

    {details, _compacted?} =
      if relevance_score(safe_json(details), terms) > 0,
        do: {details, false},
        else: compact_json_value(details, terms, max_bytes)

    if is_map(details) do
      put_context_value(character, Atom.to_string(key), details)
    else
      character
    end
  end

  defp compact_character_field_for_budget(character, _key, _max_bytes, _terms), do: character

  defp maybe_compact_character_voice(character, true, _terms), do: character

  defp maybe_compact_character_voice(character, false, terms),
    do: compact_character_field_for_budget(character, :voice_guidance, 240, terms)

  defp compact_character_activity_for_budget(character, terms) do
    activity = value(character, :visible_activity)

    if is_binary(activity) and String.length(activity) > @max_character_activity_chars and
         relevance_score(activity, terms) == 0 do
      put_context_value(
        character,
        "visible_activity",
        compact_text(activity, @max_character_activity_chars)
      )
    else
      character
    end
  end

  defp compact_panel_values_for_budget(context, terms) do
    panels = value(context, :panels)

    if is_list(panels) do
      panels = Enum.map(panels, &compact_panel_for_budget(&1, terms))
      put_context_value(context, "panels", panels)
    else
      context
    end
  end

  defp compact_panel_for_budget(panel, terms) when is_map(panel) do
    panel_value = value(panel, :value)
    panel_text = safe_json(Map.drop(panel, [:value, "value"]))
    relevant? = relevance_score(panel_text, terms) > 0

    if not relevant? and is_binary(panel_value) and String.length(panel_value) > 280 do
      put_context_value(panel, "value", compact_text(panel_value, 280))
    else
      panel
    end
  end

  defp compact_panel_for_budget(panel, _terms), do: panel

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

  # Under real size pressure, retain every inventory row and compact only
  # verbose details unrelated to the current action. A specific item mention
  # lets us shorten sibling notes; a broad inventory question keeps the full
  # ledger detail even when it means sending a request above the soft target.
  # The complete inventory remains canonical in the database and is still used
  # when validating any proposed item operation.
  defp compact_inventory_details_for_budget(context, terms) do
    inventory = value(context, :inventory)

    if is_map(inventory) do
      all_items = inventory |> Map.values() |> List.flatten()
      explicitly_named_item? = Enum.any?(all_items, &inventory_item_named_in_action?(&1, terms))
      broad_inventory_request? = not MapSet.disjoint?(MapSet.new(terms), @broad_inventory_terms)

      compacted =
        Map.new(inventory, fn {visibility, items} ->
          if is_list(items) do
            rows =
              Enum.map(items, fn item ->
                keep_detail? =
                  (explicitly_named_item? and inventory_item_named_in_action?(item, terms)) or
                    relevance_score(inventory_detail_text(item), terms) > 0 or
                    (broad_inventory_request? and not explicitly_named_item?)

                if keep_detail? do
                  item
                else
                  compact_inventory_item(item)
                end
              end)

            {visibility, rows}
          else
            {visibility, items}
          end
        end)

      put_context_value(context, "inventory", compacted)
    else
      context
    end
  end

  # World maps and tracked panels are canonical in storage but have no useful
  # per-campaign count bound. Keep the exact scene anchors and action-relevant
  # entries in the request; don't resend a growing catalog of unrelated data.
  # The completeness flags tell the GM that an omitted key is not evidence of
  # absence. This projection never overwrites the canonical stored records.
  defp project_relevant_world_state(context) do
    world = value(context, :world)

    if is_map(world) do
      terms = query_terms(context)

      {projected, {fields_omitted?, details_compacted?}} =
        Enum.map_reduce(world, {false, false}, fn {visibility, scope},
                                                  {any_fields_omitted?, any_details_compacted?} ->
          {scope, fields_omitted_here?, details_compacted_here?} =
            project_world_scope(scope, terms, visibility)

          {{visibility, scope},
           {any_fields_omitted? or fields_omitted_here?,
            any_details_compacted? or details_compacted_here?}}
        end)
        |> then(fn {groups, flags} -> {Map.new(groups), flags} end)

      {put_context_value(context, "world", projected), fields_omitted?, details_compacted?}
    else
      {context, false, false}
    end
  end

  defp project_world_scope(scope, terms, visibility) when is_map(scope) do
    source_bytes = byte_size(Jason.encode!(scope))

    if source_bytes <= @max_world_scope_bytes do
      {scope, false, false}
    else
      public_core_keys = MapSet.new(["date", "time", "weather", "location"])

      scored_fields =
        Enum.map(scope, fn {key, field_value} ->
          key_text = to_string(key)
          score = relevance_score(key_text <> " " <> safe_json(field_value), terms)

          core? =
            visibility in [:public, "public"] and
              MapSet.member?(public_core_keys, String.downcase(key_text))

          {{key, field_value}, score, core?}
        end)

      core_fields = Enum.filter(scored_fields, &elem(&1, 2))

      relevant_fields =
        scored_fields
        |> Enum.reject(&elem(&1, 2))
        |> Enum.filter(&(elem(&1, 1) > 0))
        |> Enum.sort_by(fn {{key, _value}, score, _core?} -> {-score, to_string(key)} end)

      fallback_fields =
        if core_fields == [] and relevant_fields == [],
          do:
            scored_fields
            |> Enum.sort_by(fn {{key, _value}, _score, _core?} -> to_string(key) end)
            |> Enum.take(4),
          else: []

      candidates = core_fields ++ relevant_fields ++ fallback_fields

      {selected, details_compacted?} =
        Enum.reduce(candidates, {%{}, false}, fn {{key, field_value}, score, core?},
                                                 {acc, any_compacted?} ->
          {field_value, compacted?} =
            if core? or score > 0,
              do: {field_value, false},
              else: compact_json_value(field_value, terms, @max_world_value_bytes)

          candidate = Map.put(acc, key, field_value)
          candidate_bytes = byte_size(Jason.encode!(candidate))

          if candidate_bytes <= @max_world_scope_bytes do
            {candidate, any_compacted? or compacted?}
          else
            {acc, any_compacted? or compacted?}
          end
        end)

      {selected, map_size(selected) < map_size(scope), details_compacted?}
    end
  end

  defp project_world_scope(scope, _terms, _visibility), do: {scope, false, false}

  defp compact_json_value(value, terms, max_bytes) do
    encoded = safe_json(value)

    if byte_size(encoded) <= max_bytes do
      {value, false}
    else
      compact_json_value_by_type(value, terms, max_bytes)
    end
  end

  defp compact_json_value_by_type(value, _terms, max_bytes) when is_binary(value) do
    max_chars = max(max_bytes - 80, 1)
    {compact_text(value, max_chars), true}
  end

  defp compact_json_value_by_type(value, terms, max_bytes) when is_map(value) do
    ranked =
      value
      |> Enum.map(fn {key, child} ->
        score = relevance_score(to_string(key) <> " " <> safe_json(child), terms)
        {{key, child}, score}
      end)
      |> Enum.sort_by(fn {{key, _child}, score} -> {-score, to_string(key)} end)

    chosen =
      case Enum.filter(ranked, &(elem(&1, 1) > 0)) do
        [] -> Enum.take(ranked, 4)
        relevant -> Enum.take(relevant, 8)
      end

    {projected, compacted?} =
      Enum.reduce(chosen, {%{}, true}, fn {{key, child}, _score}, {acc, any_compacted?} ->
        {child, child_compacted?} = compact_json_value(child, terms, max(div(max_bytes, 4), 120))
        next = Map.put(acc, key, child)

        if byte_size(Jason.encode!(next)) <= max_bytes do
          {next, any_compacted? or child_compacted?}
        else
          {acc, true}
        end
      end)

    {projected, compacted?}
  end

  defp compact_json_value_by_type(value, terms, max_bytes) when is_list(value) do
    ranked =
      value
      |> Enum.with_index()
      |> Enum.map(fn {item, index} -> {item, index, relevance_score(safe_json(item), terms)} end)

    relevant =
      ranked
      |> Enum.filter(&(elem(&1, 2) > 0))
      |> Enum.sort_by(fn {_item, index, score} -> {-score, -index} end)
      |> Enum.take(8)

    selected = if relevant == [], do: Enum.take(ranked, 8), else: relevant

    {projected, compacted?} =
      Enum.reduce(selected, {[], true}, fn {item, _index, _score}, {acc, _any_compacted?} ->
        {item, _item_compacted?} = compact_json_value(item, terms, max(div(max_bytes, 4), 120))
        next = acc ++ [item]
        if byte_size(Jason.encode!(next)) <= max_bytes, do: {next, true}, else: {acc, true}
      end)

    {projected, compacted?}
  end

  defp compact_json_value_by_type(value, _terms, _max_bytes), do: {value, true}

  defp safe_json(value) do
    Jason.encode!(value)
  rescue
    _error -> ""
  end

  defp project_relevant_panels(context) do
    panels = value(context, :panels)

    if is_list(panels) and byte_size(Jason.encode!(panels)) > @max_panel_context_bytes do
      terms = query_terms(context)

      ranked =
        panels
        |> Enum.with_index()
        |> Enum.map(fn {panel, index} ->
          searchable =
            [
              value(panel, :key),
              value(panel, :panel),
              value(panel, :label),
              value(panel, :unit),
              value(panel, :value)
            ]
            |> Enum.map(&to_string_safe/1)
            |> Enum.join(" ")

          {panel, index, relevance_score(searchable, terms)}
        end)

      relevant =
        ranked
        |> Enum.filter(&(elem(&1, 2) > 0))
        |> Enum.sort_by(fn {_panel, index, score} -> {-score, index} end)

      baseline = Enum.take(ranked, 8)
      selected_indexes = MapSet.new(Enum.map(baseline ++ relevant, &elem(&1, 1)))

      selected =
        if length(panels) > @max_panel_context_fields do
          ranked
          |> Enum.filter(&MapSet.member?(selected_indexes, elem(&1, 1)))
        else
          ranked
        end

      {selected, values_compacted?} =
        Enum.map_reduce(selected, false, fn {panel, _index, score}, any_compacted? ->
          {panel_value, compacted?} =
            if score > 0 do
              {value(panel, :value), false}
            else
              compact_panel_value(panel)
            end

          {put_context_value(panel, "value", panel_value), any_compacted? or compacted?}
        end)

      selected = Enum.map(selected, &elem(&1, 0))

      fields_omitted? = length(selected) < length(panels)

      {put_context_value(context, "panels", selected), fields_omitted?, values_compacted?}
    else
      {context, false, false}
    end
  end

  defp compact_panel_value(panel) do
    panel_value = value(panel, :value)
    type = value(panel, :type)

    if type in [:text, "text"] and is_binary(panel_value) and
         String.length(panel_value) > @max_panel_value_chars do
      {compact_text(panel_value, @max_panel_value_chars), true}
    else
      {panel_value, false}
    end
  end

  defp to_string_safe(nil), do: ""
  defp to_string_safe(value) when is_binary(value), do: value
  defp to_string_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp to_string_safe(value), do: safe_json(value)

  defp inventory_detail_text(item) when is_map(item) do
    properties = value(item, :properties)

    property_text =
      case properties do
        properties when is_map(properties) ->
          Enum.map_join(properties, " ", fn {_key, property_value} ->
            to_string_safe(property_value)
          end)

        properties when is_list(properties) ->
          Enum.map_join(properties, " ", &to_string_safe/1)

        _ ->
          ""
      end

    [
      value(item, :description),
      property_text
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp inventory_detail_text(_item), do: ""

  defp inventory_item_named_in_action?(item, terms) when is_map(item) do
    name_terms =
      case value(item, :name) do
        name when is_binary(name) -> raw_meaningful_terms(name)
        _ -> MapSet.new()
      end

    distinctive_name_terms = MapSet.difference(name_terms, @broad_inventory_terms)

    not MapSet.disjoint?(distinctive_name_terms, MapSet.new(terms))
  end

  defp inventory_item_named_in_action?(_item, _terms), do: false

  defp compact_inventory_item(item) when is_map(item),
    do: Map.drop(item, [:description, "description", :properties, "properties"])

  defp compact_inventory_item(item), do: item

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
    |> String.normalize(:nfc)
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

  defp compact_characters(characters, terms, player_place_id, context)
       when is_list(characters) do
    recent_speakers = recent_history_speaker_ids(value(context, :history))
    action = value(context, :player_action) || ""
    action_terms = raw_meaningful_terms(action)

    ranked =
      characters
      |> Enum.with_index()
      |> Enum.map(fn {character, index} ->
        {character, index,
         character_relevance_score(
           character,
           action,
           action_terms,
           player_place_id,
           recent_speakers
         )}
      end)

    retained_indexes = MapSet.new(ranked, fn {_character, index, _score} -> index end)

    detailed_indexes =
      ranked
      |> Enum.filter(fn {character, _index, score} ->
        score > 0 or value(character, :speaker_id) == "player"
      end)
      |> Enum.sort_by(fn {_character, index, score} -> {-score, index} end)
      |> MapSet.new(fn {_character, index, _score} -> index end)

    {compacted, {remote_profiles_omitted?, details_compacted?, rows_omitted?}} =
      Enum.reduce(ranked, {[], {false, false, false}}, fn
        {character, index, _score}, {rows, {remote_omitted?, details_omitted?, rows_omitted?}} ->
          if MapSet.member?(retained_indexes, index) do
            scene_character? =
              value(character, :speaker_id) == "player" or
                (is_binary(player_place_id) and
                   value(character, :current_place_id) == player_place_id)

            if MapSet.member?(detailed_indexes, index) do
              {rows ++ [character], {remote_omitted?, details_omitted?, rows_omitted?}}
            else
              {compact, compacted?} =
                compact_character_profile(
                  character,
                  terms,
                  MapSet.member?(detailed_indexes, index)
                )

              remote? = not scene_character?

              {rows ++ [compact],
               {remote_omitted? or remote?, details_omitted? or compacted?, rows_omitted?}}
            end
          else
            {rows, {remote_omitted?, details_omitted?, true}}
          end
      end)

    {compacted, remote_profiles_omitted?, details_compacted?, rows_omitted?}
  end

  defp compact_characters(characters, _terms, _player_place_id, _context),
    do: {characters, false, false, false}

  defp character_relevance_score(
         character,
         action,
         action_terms,
         player_place_id,
         recent_speakers
       ) do
    speaker_id = value(character, :speaker_id)
    place_id = value(character, :current_place_id)
    mentioned? = name_explicitly_mentioned?(value(character, :name), action)
    scene_character? = is_binary(player_place_id) and place_id == player_place_id
    recent_speaker? = is_binary(speaker_id) and MapSet.member?(recent_speakers, speaker_id)

    facts_score =
      [value(character, :visible_facts), value(character, :gm_private_facts)]
      |> Enum.filter(&is_map/1)
      |> Enum.map(&relevance_score(safe_json(&1), action_terms))
      |> Enum.max(fn -> 0 end)

    cond do
      speaker_id == "player" -> 10_000
      mentioned? -> 9_000 + facts_score
      recent_speaker? -> 8_000 + facts_score
      scene_character? -> 7_000 + facts_score
      facts_score > 0 -> 3_000 + facts_score
      true -> 0
    end
  end

  defp recent_history_speaker_ids(history) when is_list(history) do
    history
    |> Enum.filter(&conversation_event?/1)
    |> Enum.take(-@recent_history_count)
    |> Enum.map(&value(&1, :speaker_id))
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp recent_history_speaker_ids(_history), do: MapSet.new()

  defp compact_character_profile(character, terms, include_details?) do
    current_place = value(character, :current_place)

    profile =
      character
      |> Map.take([
        "speaker_id",
        "name",
        "role",
        "current_place_id",
        "active_duty",
        "duty_name",
        "duty_place_id",
        "duty_release_at_world_minute",
        :speaker_id,
        :name,
        :role,
        :current_place_id,
        :active_duty,
        :duty_name,
        :duty_place_id,
        :duty_release_at_world_minute
      ])
      |> then(fn profile ->
        if is_map(current_place),
          do: maybe_put_context(profile, "current_place", compact_place_identity(current_place)),
          else: profile
      end)

    {profile, facts_compacted?} =
      if include_details? do
        Enum.reduce(
          [
            visible_facts: @max_character_fact_bytes,
            gm_private_facts: @max_character_fact_bytes
          ],
          {profile, false},
          fn {key, max_bytes}, {acc, any_compacted?} ->
            facts = value(character, key)
            {facts, compacted?} = compact_json_value(facts, terms, max_bytes)

            acc =
              if is_map(facts) and map_size(facts) > 0,
                do: put_context_value(acc, Atom.to_string(key), facts),
                else: acc

            {acc, any_compacted? or compacted?}
          end
        )
      else
        facts = value(character, :visible_facts)
        facts = if is_map(facts) and byte_size(safe_json(facts)) <= 256, do: facts, else: nil

        profile =
          if is_map(facts),
            do: put_context_value(profile, "visible_facts", facts),
            else: profile

        {profile, not is_nil(value(character, :visible_facts)) and is_nil(facts)}
      end

    {profile, voice_compacted?} =
      if include_details? do
        voice = value(character, :voice_guidance)
        {voice, compacted?} = compact_json_value(voice, terms, @max_character_voice_bytes)

        profile =
          if is_map(voice) and map_size(voice) > 0,
            do: put_context_value(profile, "voice_guidance", voice),
            else: profile

        {profile, compacted?}
      else
        {profile, false}
      end

    activity = value(character, :visible_activity)

    {activity, activity_compacted?} =
      if is_binary(activity) and String.length(activity) > @max_character_activity_chars do
        {compact_text(activity, @max_character_activity_chars), true}
      else
        {activity, false}
      end

    profile =
      if is_binary(activity) do
        put_context_value(profile, "visible_activity", activity)
      else
        profile
      end

    {profile, facts_compacted? or voice_compacted? or activity_compacted? or profile != character}
  end

  defp character_facts_relevant?(character, terms) do
    [value(character, :visible_facts), value(character, :gm_private_facts)]
    |> Enum.filter(&is_map/1)
    |> Enum.any?(fn facts -> relevance_score(Jason.encode!(facts), terms) > 0 end)
  end

  defp name_explicitly_mentioned?(name, action) when is_binary(name) and is_binary(action) do
    name = name |> String.normalize(:nfc) |> String.downcase() |> String.trim()
    action = action |> String.normalize(:nfc) |> String.downcase()

    name != "" and String.contains?(action, name)
  end

  defp name_explicitly_mentioned?(_name, _action), do: false

  defp compact_places(places, _terms, player_place_id, context) when is_map(places) do
    edges = Map.get(context, "travel_connections", context[:travel_connections]) || %{}
    action = value(context, :player_action) || ""
    action_terms = raw_meaningful_terms(action)

    adjacent_ids =
      edges
      |> all_edges()
      |> Enum.flat_map(fn edge ->
        a = value(edge, :place_a_id)
        b = value(edge, :place_b_id)

        cond do
          a == player_place_id -> [b]
          b == player_place_id -> [a]
          true -> []
        end
      end)
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    relevant_character_place_ids =
      context
      |> value(:characters)
      |> List.wrap()
      |> Enum.filter(fn character ->
        speaker_id = value(character, :speaker_id)

        speaker_id == "player" or value(character, :current_place_id) == player_place_id or
          name_explicitly_mentioned?(value(character, :name), action) or
          character_facts_relevant?(character, action_terms)
      end)
      |> Enum.map(&value(&1, :current_place_id))
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    ranked_places =
      Enum.flat_map(places, fn {visibility, place_rows} ->
        if is_list(place_rows) do
          Enum.map(place_rows, fn place ->
            {visibility, place,
             place_relevance_score(
               place,
               action,
               action_terms,
               player_place_id,
               adjacent_ids,
               relevant_character_place_ids
             )}
          end)
        else
          []
        end
      end)

    retained_place_ids =
      MapSet.new(ranked_places, fn {_visibility, place, _score} ->
        value(place, :place_id)
      end)

    detailed_place_ids =
      ranked_places
      |> Enum.filter(fn {_visibility, _place, score} -> score > 0 end)
      |> Enum.sort_by(fn {_visibility, place, score} ->
        {-score, value(place, :place_id) || value(place, :name) || ""}
      end)
      |> MapSet.new(fn {_visibility, place, _score} -> value(place, :place_id) end)

    {result, {details_omitted?, details_compacted?, rows_omitted?}} =
      Enum.map_reduce(places, {false, false, false}, fn {visibility, place_rows},
                                                        {any_omitted?, any_compacted?,
                                                         any_rows_omitted?} ->
        if is_list(place_rows) do
          {rows, {omitted_here?, compacted_here?, rows_omitted_here?}} =
            Enum.reduce(place_rows, {[], {false, false, false}}, fn place,
                                                                    {rows,
                                                                     {details_omitted?,
                                                                      details_compacted?,
                                                                      rows_omitted?}} ->
              place_id = value(place, :place_id)

              cond do
                not MapSet.member?(retained_place_ids, place_id) ->
                  {rows, {true, details_compacted?, true}}

                MapSet.member?(detailed_place_ids, place_id) ->
                  {rows ++ [place], {details_omitted?, details_compacted?, rows_omitted?}}

                true ->
                  {rows ++ [compact_place_identity(place)],
                   {true, details_compacted?, rows_omitted?}}
              end
            end)

          {{visibility, rows},
           {any_omitted? or omitted_here?, any_compacted? or compacted_here?,
            any_rows_omitted? or rows_omitted_here?}}
        else
          {{visibility, place_rows}, {any_omitted?, any_compacted?, any_rows_omitted?}}
        end
      end)
      |> then(fn {groups, omissions} -> {Map.new(groups), omissions} end)

    {result, details_omitted?, details_compacted?, rows_omitted?}
  end

  defp compact_places(places, _terms, _player_place_id, _context),
    do: {places, false, false, false}

  defp place_relevance_score(
         place,
         action,
         action_terms,
         player_place_id,
         adjacent_ids,
         character_place_ids
       ) do
    place_id = value(place, :place_id)
    action_fact_terms = MapSet.intersection(meaningful_terms(safe_json(place)), action_terms)
    fact_score = MapSet.size(action_fact_terms)
    place_name = value(place, :name)

    explicitly_named? =
      is_binary(place_name) and is_binary(action) and
        String.contains?(String.downcase(action), String.downcase(place_name))

    cond do
      place_id == player_place_id -> 10_000
      explicitly_named? -> 9_000
      MapSet.member?(character_place_ids, place_id) -> 8_000
      MapSet.member?(adjacent_ids, place_id) -> 7_000
      fact_score >= 2 -> 3_000 + fact_score
      true -> 0
    end
  end

  defp compact_place_identity(place) when is_map(place) do
    Map.take(place, ["place_id", "name", "visibility", :place_id, :name, :visibility])
  end

  defp compact_place_identity(_place), do: nil

  defp compact_continuity(continuity, terms) when is_map(continuity) do
    {groups, {details_omitted?, rows_omitted?}} =
      Enum.map_reduce(continuity, {false, false}, fn {visibility, entries},
                                                     {any_details_omitted?, any_rows_omitted?} ->
        entries = if is_list(entries), do: entries, else: []

        recent_start = max(length(entries) - @max_continuity_context_rows, 0)

        recent_indexes =
          if entries == [], do: [], else: Enum.to_list(recent_start..(length(entries) - 1))

        relevant_or_active_indexes =
          entries
          |> Enum.with_index()
          |> Enum.filter(fn {entry, _index} ->
            memory_relevant?(entry, terms) or
              relevance_score(entry_text(entry), terms) > 0
          end)
          |> Enum.map(&elem(&1, 1))

        retained_indexes = MapSet.new(relevant_or_active_indexes ++ recent_indexes)

        detailed_ids =
          entries
          |> Enum.with_index()
          |> Enum.filter(fn {entry, index} ->
            MapSet.member?(retained_indexes, index) and
              (memory_relevant?(entry, terms) or relevance_score(entry_text(entry), terms) > 0)
          end)
          |> MapSet.new(fn {entry, _index} -> value(entry, :entry_id) end)

        {rows, {details_omitted_here?, rows_omitted_here?}} =
          entries
          |> Enum.with_index()
          |> Enum.reduce({[], {false, false}}, fn {entry, index},
                                                  {rows,
                                                   {any_details_omitted?, any_rows_omitted?}} ->
            if not MapSet.member?(retained_indexes, index) do
              {rows, {any_details_omitted?, true}}
            else
              active? = value(entry, :status) in ["active", :active]
              mentioned? = relevance_score(entry_text(entry), terms) > 0

              recent? = MapSet.member?(retained_indexes, index) and index >= recent_start

              # Active records stay queryable locally. In the prompt, preserve
              # all matched memories and recent active commitments; do not let
              # an unrelated active ledger grow without bound.
              if MapSet.member?(detailed_ids, value(entry, :entry_id)) or mentioned? or
                   (active? and recent?) do
                {rows ++ [entry], {any_details_omitted?, any_rows_omitted?}}
              else
                compact = Map.drop(entry, [:details, "details", :title, "title"])
                {rows ++ [compact], {any_details_omitted? or compact != entry, any_rows_omitted?}}
              end
            end
          end)

        {{visibility, rows},
         {any_details_omitted? or details_omitted_here?, any_rows_omitted? or rows_omitted_here?}}
      end)

    result = Map.new(groups)
    omitted? = details_omitted? or rows_omitted? or result != continuity
    {result, omitted?}
  end

  defp compact_continuity(continuity, _terms), do: {continuity, false}

  defp compact_objectives(objectives, terms) when is_map(objectives) do
    {groups, {rows_omitted?, details_omitted?, closed_details_omitted?}} =
      Enum.map_reduce(objectives, {false, false, false}, fn {visibility, rows},
                                                            {any_rows_omitted?,
                                                             any_details_omitted?,
                                                             any_closed_details_omitted?} ->
        rows = if is_list(rows), do: rows, else: []

        ranked =
          rows
          |> Enum.with_index()
          |> Enum.map(fn {objective, index} ->
            {objective, index, relevance_score(entry_text(objective), terms)}
          end)

        relevant =
          ranked
          |> Enum.filter(&(elem(&1, 2) > 0))
          |> Enum.sort_by(fn {_objective, index, score} -> {-score, -index} end)

        recent_open =
          ranked
          |> Enum.reverse()
          |> Enum.filter(fn {objective, _index, _score} ->
            value(objective, :status) in ["open", :open]
          end)
          |> Enum.take(@max_open_objective_rows)

        recent_closed =
          ranked
          |> Enum.reverse()
          |> Enum.filter(fn {objective, _index, _score} -> objective_closed?(objective) end)
          |> Enum.take(8)

        retained_indexes =
          MapSet.new(relevant ++ recent_open ++ recent_closed, fn {_objective, index, _score} ->
            index
          end)

        detailed_indexes =
          ranked
          |> Enum.filter(fn {_objective, index, _score} ->
            MapSet.member?(retained_indexes, index)
          end)
          |> Enum.reject(fn {objective, _index, score} ->
            objective_closed?(objective) and score == 0
          end)
          |> MapSet.new(fn {_objective, index, _score} -> index end)

        {selected, {rows_omitted_here?, details_omitted_here?, closed_details_omitted_here?}} =
          ranked
          |> Enum.filter(fn {_objective, index, _score} ->
            MapSet.member?(retained_indexes, index)
          end)
          |> Enum.map_reduce({false, false, false}, fn {objective, index, _score},
                                                       {row_omitted?, detail_omitted?,
                                                        closed_detail_omitted?} ->
            closed? = objective_closed?(objective)
            details = value(objective, :details)

            if MapSet.member?(detailed_indexes, index) and is_binary(details) do
              {put_context_value(objective, "details", details),
               {row_omitted?, detail_omitted?, closed_detail_omitted?}}
            else
              if is_binary(details) do
                {Map.drop(objective, [:details, "details"]),
                 {row_omitted?, true, closed_detail_omitted? or closed?}}
              else
                {objective, {row_omitted?, detail_omitted?, closed_detail_omitted?}}
              end
            end
          end)

        {{visibility, selected},
         {any_rows_omitted? or length(rows) > length(selected) or rows_omitted_here?,
          any_details_omitted? or details_omitted_here?,
          any_closed_details_omitted? or closed_details_omitted_here?}}
      end)
      |> then(fn {groups, omissions} -> {Map.new(groups), omissions} end)

    {groups, rows_omitted?, details_omitted?, closed_details_omitted?}
  end

  defp compact_objectives(objectives, _terms), do: {objectives, false, false, false}

  defp objective_closed?(objective),
    do: value(objective, :status) in ["completed", "abandoned", :completed, :abandoned]

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
      suffix =
        cond do
          max_chars <= 1 -> ""
          max_chars <= 48 -> "…"
          true -> " … [context excerpt; older text omitted]"
        end

      suffix = String.slice(suffix, 0, max_chars)
      prefix_length = max(max_chars - String.length(suffix), 0)

      String.slice(text, 0, prefix_length) <> suffix
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
    text_terms = raw_meaningful_terms(text)
    Enum.count(terms, &MapSet.member?(text_terms, &1))
  end

  defp relevance_score(_text, _terms), do: 0

  defp name_mentioned?(name, terms) when is_binary(name) do
    name_terms = raw_meaningful_terms(name)

    MapSet.size(name_terms) > 0 and MapSet.size(terms) > 0 and
      not MapSet.disjoint?(name_terms, terms)
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
