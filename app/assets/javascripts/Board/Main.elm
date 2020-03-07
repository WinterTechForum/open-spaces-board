module Board exposing (..)

import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Set exposing (Set)
import WebSocket


type Operation = Add | Remove


type alias DataManipulation =
  { type_ : String
  , operation : Operation
  , key : String
  , value : Maybe Decode.Value
  }


type alias Topic =
  { text : String
  , convener : String
  }


type alias Model =
  { webSocketUrl : String
  , rooms : Set String
  , timeSlots : Set String
  , topicIdsByTimeSlotRoom : Dict (String, String) String
  , topicsById : Dict String Topic
  , timeSlotRoomsByTopicId : Dict String (String, String)
  , countTopicAddingDataManipulations : Int
  , workingTopic : Maybe (Maybe (String, String), String, Topic)
  , movingTopicId : Maybe String
  , movingDestinationCandidate : Maybe (String, String)
  }


type Msg
  = WebSocketMessage String
  | ShowAddTopicViewRequest String String
  | ShowEditTopicViewRequest String Topic
  | UpdateWorkingTopicText String
  | UpdateWorkingTopicConvener String
  | DeleteWorkingTopic
  | SelectTopicToMove String
  | DraggingOverRoomTimeSlot String String
  | MoveTopicToRoomTimeSlot String String
  | CreateTopicRequest
  | DeleteTopicRequest String


-- Init
init : String -> (Model, Cmd Msg)
init webSocketBaseUrl =
  ( Model (webSocketBaseUrl ++ "/store")
    Set.empty Set.empty Dict.empty Dict.empty Dict.empty 0
    Nothing Nothing Nothing
  , Cmd.none
  )


-- Update
dataManipulationDecoder : Decoder DataManipulation
dataManipulationDecoder =
  Decode.map4
    DataManipulation
    ( Decode.field "type" Decode.string )
    ( Decode.map
      ( \opCode ->
        case opCode of
          "+" -> Add
          _ -> Remove
      )
      ( Decode.field "op" Decode.string )
    )
    ( Decode.field "key" Decode.string )
    ( Decode.maybe ( Decode.field "value" Decode.value ) )


topicDecoder : Decoder Topic
topicDecoder =
  Decode.map2
    Topic
    ( Decode.field "text" Decode.string )
    ( Decode.field "convener" Decode.string )


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    WebSocketMessage body ->
      let
        dataManipulationsRes : Result String (List DataManipulation)
        dataManipulationsRes = Decode.decodeString (Decode.list dataManipulationDecoder) body
      in
        ( case dataManipulationsRes of
            Ok dataManipulations ->
              List.foldr
              ( \dataManipulation -> \accumModel ->
                case dataManipulation.type_ of
                  "*" ->
                    case dataManipulation.operation of
                      Add -> accumModel
                      Remove ->
                        { accumModel
                        | rooms = Set.empty
                        , timeSlots = Set.empty
                        , topicIdsByTimeSlotRoom = Dict.empty
                        , topicsById = Dict.empty
                        , timeSlotRoomsByTopicId = Dict.empty
                        }

                  "timeSlot" ->
                    case dataManipulation.operation of
                      Add ->
                        { accumModel
                        | timeSlots = Set.insert dataManipulation.key accumModel.timeSlots
                        }
                      Remove ->
                        { accumModel
                        | timeSlots = Set.remove dataManipulation.key accumModel.timeSlots
                        , topicIdsByTimeSlotRoom =
                          Dict.filter
                          ( \(timeSlot, _) -> \_ -> timeSlot /= dataManipulation.key )
                          accumModel.topicIdsByTimeSlotRoom
                        , timeSlotRoomsByTopicId =
                          Dict.filter
                          ( \_ -> \(timeSlot, _) -> timeSlot /= dataManipulation.key )
                          accumModel.timeSlotRoomsByTopicId
                        }

                  "room" ->
                    case dataManipulation.operation of
                      Add ->
                        { accumModel
                        | rooms = Set.insert dataManipulation.key accumModel.rooms
                        }
                      Remove ->
                        { accumModel
                        | rooms = Set.remove dataManipulation.key accumModel.rooms
                        , topicIdsByTimeSlotRoom =
                          Dict.filter
                          ( \(_, room) -> \_ -> room /= dataManipulation.key )
                          accumModel.topicIdsByTimeSlotRoom
                        , timeSlotRoomsByTopicId =
                          Dict.filter
                          ( \_ -> \(_, room) -> room /= dataManipulation.key )
                          accumModel.timeSlotRoomsByTopicId
                        }

                  "topic" ->
                    case dataManipulation.operation of
                      Add ->
                        case dataManipulation.value of
                          Just value ->
                            case Decode.decodeValue topicDecoder value of
                              Ok topic ->
                                { accumModel
                                | topicsById = Dict.insert dataManipulation.key topic accumModel.topicsById
                                -- Note use of `model` here - incrementing by 1 regardless of # of new topics
                                , countTopicAddingDataManipulations = model.countTopicAddingDataManipulations + 1
                                }
                              Err _ -> accumModel
                          Nothing -> accumModel
                      Remove ->
                        { accumModel
                        | topicsById = Dict.remove dataManipulation.key accumModel.topicsById
                        }

                  "pin" ->
                    case dataManipulation.value of
                      Just value ->
                        case Decode.decodeValue Decode.string value of
                          Ok topicId ->
                            case String.split "|" dataManipulation.key of
                              [ timeSlot, room ] ->
                                let
                                  (unpinnedTopicIdsByTimeSlotRoom, displacedTimeSlotRoomsByTopicId) =
                                    case Dict.get topicId accumModel.timeSlotRoomsByTopicId of
                                      Just oldTimeSlotRoom ->
                                        case Dict.get (timeSlot, room) accumModel.topicIdsByTimeSlotRoom of
                                          Just displacedTopicId ->
                                            ( Dict.insert oldTimeSlotRoom displacedTopicId accumModel.topicIdsByTimeSlotRoom
                                            , Dict.remove displacedTopicId accumModel.timeSlotRoomsByTopicId
                                            )
                                          Nothing ->
                                            ( Dict.remove oldTimeSlotRoom accumModel.topicIdsByTimeSlotRoom
                                            , accumModel.timeSlotRoomsByTopicId
                                            )
                                      Nothing ->
                                        case Dict.get (timeSlot, room) accumModel.topicIdsByTimeSlotRoom of
                                          Just displacedTopicId ->
                                            ( accumModel.topicIdsByTimeSlotRoom
                                            , Dict.remove displacedTopicId accumModel.timeSlotRoomsByTopicId
                                            )
                                          Nothing ->
                                            ( accumModel.topicIdsByTimeSlotRoom
                                            , accumModel.timeSlotRoomsByTopicId
                                            )
                                in
                                  { accumModel
                                  | topicIdsByTimeSlotRoom =
                                    Dict.insert
                                    (timeSlot, room)
                                    topicId
                                    unpinnedTopicIdsByTimeSlotRoom
                                  , timeSlotRoomsByTopicId =
                                    Dict.insert
                                    topicId
                                    (timeSlot, room)
                                    displacedTimeSlotRoomsByTopicId
                                  }
                              _ -> accumModel
                          Err _ -> accumModel
                      Nothing -> accumModel

                  _ -> accumModel
              )
              model
              dataManipulations

            Err _ -> model
        , Cmd.none
        )

    ShowAddTopicViewRequest timeSlot room ->
      ( { model | workingTopic = Just (Just (timeSlot, room), "new", Topic "" "") }
      , Cmd.none
      )

    ShowEditTopicViewRequest topicId topic ->
      ( { model | workingTopic = Just (Nothing, topicId, topic) }
      , Cmd.none
      )

    UpdateWorkingTopicText text ->
      let
        workingTopic : Maybe (Maybe (String, String), String, Topic)
        workingTopic =
          Maybe.map
          ( \(maybeTimeSlotRoom, topicId, topic) -> (maybeTimeSlotRoom, topicId, { topic | text = text }) )
          model.workingTopic
      in
        ( { model | workingTopic = workingTopic }
        , Cmd.none
        )

    UpdateWorkingTopicConvener convener ->
      let
        workingTopic : Maybe (Maybe (String, String), String, Topic)
        workingTopic =
          Maybe.map
          ( \(maybeTimeSlotRoom, topicId, topic) -> (maybeTimeSlotRoom, topicId, { topic | convener = convener }) )
          model.workingTopic
      in
        ( { model | workingTopic = workingTopic }
        , Cmd.none
        )

    DeleteWorkingTopic ->
      ( { model | workingTopic = Nothing }
      , Cmd.none
      )

    SelectTopicToMove topicId ->
      ( { model | movingTopicId = Just topicId }
      , Cmd.none
      )

    DraggingOverRoomTimeSlot timeSlot room ->
      ( { model | movingDestinationCandidate = Just (timeSlot, room) }
      , Cmd.none
      )

    MoveTopicToRoomTimeSlot timeSlot room ->
      ( { model | movingTopicId = Nothing, movingDestinationCandidate = Nothing }
      , case model.movingTopicId of
          Just topicId ->
            if Maybe.withDefault False (Maybe.map ((==) (timeSlot,room)) (Dict.get topicId model.timeSlotRoomsByTopicId)) then
              Cmd.none
            else
              WebSocket.send model.webSocketUrl
              ( Encode.encode 0
                ( Encode.list
                  [ Encode.object
                    [ ( "type", Encode.string "pin" )
                    , ( "op",  Encode.string "+" )
                    , ( "key", Encode.string (timeSlot ++ "|" ++ room) )
                    , ( "value", Encode.string topicId )
                    ]
                  ]
                )
              )

          Nothing -> Cmd.none
      )

    CreateTopicRequest ->
      ( { model | workingTopic = Nothing }
      , case model.workingTopic of
          Just (maybeTimeSlotRoom, topicId, topic) ->
            WebSocket.send model.webSocketUrl
            ( Encode.encode 0
              ( Encode.list
                (List.filterMap
                  identity
                  [ Maybe.map
                    ( \(timeSlot, room) ->
                      Encode.object
                      [ ( "type", Encode.string "pin" )
                      , ( "op",  Encode.string "+" )
                      , ( "key", Encode.string (timeSlot ++ "|" ++ room) )
                      , ( "value", Encode.string topicId )
                      ]
                    )
                    maybeTimeSlotRoom
                  , Just
                    ( Encode.object
                      [ ( "type", Encode.string "topic" )
                      , ( "op", Encode.string "+" )
                      , ( "key", Encode.string topicId )
                      , ( "value"
                        , Encode.object
                          [ ( "text", Encode.string topic.text )
                          , ( "convener", Encode.string topic.convener )
                          ]
                        )
                      ]
                    )
                  ]
                )
              )
            )

          Nothing -> Cmd.none
      )

    DeleteTopicRequest topicId ->
      ( model
      , WebSocket.send model.webSocketUrl
        ( Encode.encode 0
          ( Encode.list
            [ Encode.object
              [ ( "type", Encode.string "topic" )
              , ( "op", Encode.string "-" )
              , ( "key", Encode.string topicId )
              ]
            ]
          )
        )
      )


-- Subscription
subscriptions : Model -> Sub Msg
subscriptions model =
  WebSocket.listen model.webSocketUrl WebSocketMessage


-- View
onDragStart : msg -> Attribute msg
onDragStart msg =
  on "dragstart" (Decode.succeed msg)


onDragOver : msg -> Attribute msg
onDragOver msg =
  onWithOptions "dragover" { defaultOptions | preventDefault = True } (Decode.succeed msg)


onDrop : msg -> Attribute msg
onDrop msg =
  onWithOptions "drop" { defaultOptions | preventDefault = True } (Decode.succeed msg)


topicView : String -> Topic -> Html Msg
topicView topicId topic =
  div [ id topicId, class "topic", draggable "true", onDragStart (SelectTopicToMove topicId) ]
  [ div [] [ text topic.text ]
  , div [ style [ ("font-size", "0.8em") ] ] [ text ("Convener: " ++ topic.convener) ]
  , button
    [ onClick (ShowEditTopicViewRequest topicId topic) ]
    [ text "Edit" ]
  , button
    [ onClick (DeleteTopicRequest topicId) ]
    [ text "Delete" ]
  ]


view : Model -> Html Msg
view model =
  case model.workingTopic of
    Just (_, _, topic) ->
      div []
      [ div []
        [ textarea [ onInput UpdateWorkingTopicText, cols 80, rows 10 ]
          [ text topic.text ]
        ]
      , div []
        [ text "Convener:"
        , input [ type_ "text", value topic.convener, onInput UpdateWorkingTopicConvener ] []
        ]
      , div []
        [ button [ onClick CreateTopicRequest ] [ text "Save" ]
        , button [ onClick DeleteWorkingTopic ] [ text "Cancel" ]
        ]
      ]
    Nothing ->
      div []
      [ table [ class "board", style [ ( "width", "100%" ), ( "border-collapse", "collapse" ) ] ]
        ( ( tr []
            ( ( th [] [] )
            ::( List.map
                ( \room -> th [] [ text room ] )
                ( Set.toList model.rooms )
              )
            )
          )
        ::( List.map
            ( \timeSlot ->
              tr []
              ( ( th [] [ text timeSlot ] )
              ::( List.map
                  ( \room ->
                    td
                    [ id (timeSlot ++ "|" ++ room)
                    , let
                        isDestinationCandidate : Bool
                        isDestinationCandidate =
                          Maybe.withDefault
                          False
                          ( Maybe.map
                            (\(dstTimeSlot, dstRoom) -> dstTimeSlot == timeSlot && dstRoom == room)
                            model.movingDestinationCandidate
                          )
                      in (class (if isDestinationCandidate then "destination-candidate" else ""))
                    , onDragOver (DraggingOverRoomTimeSlot timeSlot room), onDrop (MoveTopicToRoomTimeSlot timeSlot room)
                    ]
                    ( let
                        maybeTopicWithId : Maybe (String, Topic)
                        maybeTopicWithId =
                          Maybe.andThen
                          ( \topicId ->
                            Maybe.map
                            ( \topic -> (topicId, topic) )
                            ( Dict.get topicId model.topicsById )
                          )
                          ( Dict.get (timeSlot, room) model.topicIdsByTimeSlotRoom )
                      in
                        case maybeTopicWithId of
                          Just (topicId, topic) ->
                            [ topicView topicId topic ]
                          Nothing ->
                            [ button
                              [ onClick (ShowAddTopicViewRequest timeSlot room) ]
                              [ text "Add" ]
                            ]
                    )
                  )
                  ( Set.toList model.rooms )
                )
              )
            )
            ( Set.toList model.timeSlots )
          )
        )
      , h2 [] [ text "Unpinned topics" ]
      , div [ class "unpinned" ]
        ( List.filterMap
          ( \topicId ->
            Maybe.map
            ( topicView topicId )
            ( Dict.get topicId model.topicsById )
          )
          ( Set.toList
            ( Set.diff
              ( Set.fromList (Dict.keys model.topicsById) )
              ( Set.fromList (Dict.keys model.timeSlotRoomsByTopicId) )
            )
          )
        )
      , div []
        ( List.repeat model.countTopicAddingDataManipulations
          ( node "script"
            [ type_ "application/javascript"
            , src "http://bernardo-castilho.github.io/DragDropTouch/DragDropTouch.js"
            ]
            []
          )
        )
      ]


main : Program String Model Msg
main =
  Html.programWithFlags
    { init = init
    , update = update
    , subscriptions = subscriptions
    , view = view
    }
