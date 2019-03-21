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
  , topics : Dict (String, String) Topic
  , workingTopic : Maybe (String, String, Topic)
  }


type Msg
  = WebSocketMessage String
  | ShowAddTopicViewRequest String String
  | UpdateWorkingTopicText String
  | UpdateWorkingTopicConvener String
  | CreateTopicRequest


-- Init
init : String -> (Model, Cmd Msg)
init webSocketBaseUrl =
  ( Model (webSocketBaseUrl ++ "/store") Set.empty Set.empty Dict.empty Nothing
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
              let
                (workingModel, topicsById, topicIdsByTimeSlotRoom) =
                  List.foldl
                  ( \dataManipulation -> \(model, topicsById, topicIdsByTimeSlotRoom) ->
                    case dataManipulation.type_ of
                      "room" ->
                        let
                          rooms : Set String
                          rooms = model.rooms
                        in
                          ( { model
                            | rooms =
                              case dataManipulation.operation of
                                Add -> Set.insert dataManipulation.key rooms
                                Remove -> Set.remove dataManipulation.key rooms
                            }
                          , topicsById
                          , topicIdsByTimeSlotRoom
                          )

                      "timeSlot" ->
                        let
                          timeSlots : Set String
                          timeSlots = model.timeSlots
                        in
                          ( { model
                            | timeSlots =
                              case dataManipulation.operation of
                                Add -> Set.insert dataManipulation.key timeSlots
                                Remove -> Set.remove dataManipulation.key timeSlots
                            }
                          , topicsById
                          , topicIdsByTimeSlotRoom
                          )

                      "topic" ->
                        ( model
                        , case dataManipulation.value of
                            Just value ->
                              case Decode.decodeValue topicDecoder value of
                                Ok topic -> Dict.insert dataManipulation.key topic topicsById
                                Err _ -> topicsById
                            Nothing ->
                              topicsById
                        , topicIdsByTimeSlotRoom
                        )

                      "pin" ->
                        ( model
                        , topicsById
                        , case dataManipulation.value of
                            Just value ->
                              case Decode.decodeValue Decode.string value of
                                Ok topicId ->
                                  case String.split "|" dataManipulation.key of
                                    [ timeSlot, room ] ->
                                      Dict.insert
                                      (timeSlot, room)
                                      topicId
                                      topicIdsByTimeSlotRoom
                                    _ -> topicIdsByTimeSlotRoom
                                Err _ -> topicIdsByTimeSlotRoom
                            Nothing ->
                              topicIdsByTimeSlotRoom
                        )

                      _ -> (model, topicsById, topicIdsByTimeSlotRoom)
                  )
                  ( model, Dict.empty, Dict.empty )
                  dataManipulations
              in
                { workingModel
                | topics =
                  Dict.union
                  workingModel.topics
                  ( Dict.foldl
                    ( \timeSlotRoom -> \topicId -> \accumTopics ->
                      case Dict.get topicId topicsById of
                        Just topic -> Dict.insert timeSlotRoom topic accumTopics
                        Nothing -> accumTopics
                    )
                    Dict.empty
                    topicIdsByTimeSlotRoom
                  )
                }
            Err _ -> model
        , Cmd.none
        )

    ShowAddTopicViewRequest timeSlot room ->
      ( { model | workingTopic = Just (timeSlot, room, Topic "" "") }
      , Cmd.none
      )

    UpdateWorkingTopicText text ->
      let
        workingTopic : Maybe (String, String, Topic)
        workingTopic =
          Maybe.map
          ( \(timeSlot, room, topic) -> (timeSlot, room, { topic | text = text }) )
          model.workingTopic
      in
        ( { model | workingTopic = workingTopic }
        , Cmd.none
        )

    UpdateWorkingTopicConvener convener ->
      let
        workingTopic : Maybe (String, String, Topic)
        workingTopic =
          Maybe.map
          ( \(timeSlot, room, topic) -> (timeSlot, room, { topic | convener = convener }) )
          model.workingTopic
      in
        ( { model | workingTopic = workingTopic }
        , Cmd.none
        )

    CreateTopicRequest ->
      ( { model | workingTopic = Nothing }
      , case model.workingTopic of
          Just (timeSlot, room, topic) ->
            WebSocket.send model.webSocketUrl
            ( Encode.encode 0
              ( Encode.list
                [ Encode.object
                  [ ( "type", Encode.string "topic" )
                  , ( "op", Encode.string "+" )
                  , ( "key", Encode.string "new" )
                  , ( "value"
                    , Encode.object
                      [ ( "text", Encode.string topic.text )
                      , ( "convener", Encode.string topic.convener )
                      ]
                    )
                  ]
                , Encode.object
                  [ ( "type", Encode.string "pin" )
                  , ( "op", Encode.string "+" )
                  , ( "key", Encode.string (timeSlot ++ "|" ++ room) )
                  , ( "value", Encode.string "new" )
                  ]
                ]
              )
            )

          Nothing -> Cmd.none
      )


-- Subscription
subscriptions : Model -> Sub Msg
subscriptions model =
  WebSocket.listen model.webSocketUrl WebSocketMessage


-- View
tableCellStyle : List (String, String)
tableCellStyle =
  [ ( "border", "solid #ddd 1px" ) ]


view : Model -> Html Msg
view model =
  case model.workingTopic of
    Just (timeSlot, room, topic) ->
      div []
      [ div [] [ textarea [ onInput UpdateWorkingTopicText, cols 80, rows 10 ] [] ]
      , div []
        [ text "Convener:"
        , input [ type_ "text", onInput UpdateWorkingTopicConvener ] []
        ]
      , div [] [ button [ onClick CreateTopicRequest ] [ text "Save" ] ]
      ]
    Nothing ->
      div []
      [ table [ style [ ( "border-collapse", "collapse" ) ] ]
        ( ( tr []
            ( ( th [ style tableCellStyle ] [] )
            ::( List.map
                ( \room -> th [ style tableCellStyle ] [ text room ] )
                ( Set.toList model.rooms )
              )
            )
          )
        ::( List.map
            ( \timeSlot ->
              tr []
              ( ( th [ style tableCellStyle ] [ text timeSlot ] )
              ::( List.map
                  ( \room ->
                    td [ style tableCellStyle ]
                    ( case Dict.get (timeSlot, room) model.topics of
                        Just topic ->
                          [ div [] [ text topic.text ]
                          , div [ style [ ("font-size", "0.8em") ] ] [ text ("Convener: " ++ topic.convener) ]
                          ]
                        Nothing -> [ button [ onClick (ShowAddTopicViewRequest timeSlot room) ] [ text "Add" ] ]
                    )
                  )
                  ( Set.toList model.rooms )
                )
              )
            )
            ( Set.toList model.timeSlots )
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
