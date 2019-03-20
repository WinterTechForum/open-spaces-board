module Admin exposing (..)

import Date
import Html exposing (..)
import Html.Attributes exposing (disabled, type_, value)
import Html.Events exposing (onClick, onInput)
import Json.Decode as Decode exposing (Decoder)
import Set exposing (Set)
import WebSocket


type Operation = Add | Remove


type alias DataManipulation =
  { type_ : String
  , operation : Operation
  , key : String
  }


type alias Model =
  { webSocketUrl : String
  , rooms : Set String
  , newRoom : String
  , timeSlots : Set String
  , newTimeSlot : String
  , newTimeSlotValid : Bool
  }


type Msg
  = WebSocketMessage String
  | UpdatedNewRoom String
  | AddRoomRequest
  | RemoveRoomRequest String
  | UpdatedNewTimeSlot String
  | AddTimeSlotRequest
  | RemoveTimeSlotRequest String


-- Init
init : String -> (Model, Cmd Msg)
init webSocketBaseUrl =
  ( Model (webSocketBaseUrl ++ "/store") Set.empty "" Set.empty "" False
  , Cmd.none
  )


-- Update
dataManipulationDecoder : Decoder DataManipulation
dataManipulationDecoder =
  Decode.map3
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
              List.foldl
              ( \dataManipulation -> \model ->
                case dataManipulation.type_ of
                  "room" ->
                    let
                      rooms : Set String
                      rooms = model.rooms
                    in
                      { model
                      | rooms =
                        case dataManipulation.operation of
                          Add -> Set.insert dataManipulation.key rooms
                          Remove -> Set.remove dataManipulation.key rooms
                      }
                  "timeSlot" ->
                    let
                      timeSlots : Set String
                      timeSlots = model.timeSlots
                    in
                      { model
                      | timeSlots =
                        case dataManipulation.operation of
                          Add -> Set.insert dataManipulation.key timeSlots
                          Remove -> Set.remove dataManipulation.key timeSlots
                      }
                  _ -> model
              )
              model
              dataManipulations
            Err _ -> model
        , Cmd.none
        )

    UpdatedNewRoom newRoom ->
      ( { model | newRoom = newRoom }
      , Cmd.none
      )

    AddRoomRequest ->
      ( { model | newRoom = "" }
      , WebSocket.send model.webSocketUrl
        -- TODO use JSON encoder (or at least escape value)
        ( """[{"type":"room","op":"+","key":\"""" ++ model.newRoom ++ """"}]""" )
      )

    RemoveRoomRequest room ->
      ( model
      , WebSocket.send model.webSocketUrl
        -- TODO use JSON encoder (or at least escape value)
        ( """[{"type":"room","op":"-","key":\"""" ++ room ++ """"}]""" )
      )

    UpdatedNewTimeSlot newTimeSlot ->
      ( { model
        | newTimeSlot = newTimeSlot
        , newTimeSlotValid =
          case Date.fromString newTimeSlot of
            Ok _ -> True
            Err _ -> False
        }
      , Cmd.none
      )

    AddTimeSlotRequest ->
      ( { model | newTimeSlot = "" }
      , case Date.fromString model.newTimeSlot of
          Ok date ->
            WebSocket.send model.webSocketUrl
              -- TODO use JSON encoder (or at least escape value)
              ( """[{"type":"timeSlot","op":"+","key":\""""
              ++( String.slice 1 22 (toString date) )
              ++ """"}]"""
              )
          Err _ ->
            Cmd.none
      )

    RemoveTimeSlotRequest timeSlot ->
      ( model
      , WebSocket.send model.webSocketUrl
        -- TODO use JSON encoder (or at least escape value)
        ( """[{"type":"timeSlot","op":"-","key":\"""" ++ timeSlot ++ """"}]""" )
      )


-- Subscription
subscriptions : Model -> Sub Msg
subscriptions model =
  WebSocket.listen model.webSocketUrl WebSocketMessage


-- View
view : Model -> Html Msg
view model =
  ul []
  [ li []
    [ text "Rooms"
    , ul []
      ( List.map
        ( \room ->
          li []
          [ text room
          , button [ onClick (RemoveRoomRequest room) ] [ text "-" ]
          ]
        )
        ( Set.toList model.rooms )
      ++[ li []
          [ input [ type_ "text", value model.newRoom, onInput UpdatedNewRoom ] []
          , button [ onClick AddRoomRequest ] [ text "+" ]
          ]
        ]
      )
    ]
  , li []
    [ text "Time Slots"
    , ul []
      ( List.map
        ( \timeSlot ->
          li []
          [ text timeSlot
          , button [ onClick (RemoveTimeSlotRequest timeSlot) ] [ text "-" ]
          ]
        )
        ( Set.toList model.timeSlots )
      ++[ li []
          [ input [ type_ "text", value model.newTimeSlot, onInput UpdatedNewTimeSlot ] []
          , button [ onClick AddTimeSlotRequest, disabled (not model.newTimeSlotValid) ] [ text "+" ]
          ]
        ]
      )
    ]
  ]


main : Program String Model Msg
main =
  Html.programWithFlags
    { init = init
    , update = update
    , subscriptions = subscriptions
    , view = view
    }
