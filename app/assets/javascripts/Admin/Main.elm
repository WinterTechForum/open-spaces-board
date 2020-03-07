module Admin exposing (..)

import Html exposing (..)
import Html.Attributes exposing (disabled, type_, value)
import Html.Events exposing (onClick, onInput)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
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
  , newRoomValid : Bool
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
  ( Model (webSocketBaseUrl ++ "/store") Set.empty "" False Set.empty "" False
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
              List.foldr
              ( \dataManipulation -> \model ->
                case dataManipulation.type_ of
                  "*" ->
                    case dataManipulation.operation of
                      Add -> model
                      Remove ->
                        { model
                        | rooms = Set.empty
                        , timeSlots = Set.empty
                        }

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
      ( { model
        | newRoom = newRoom
        , newRoomValid = not (newRoom == "" || String.contains "|" newRoom)
        }
      , Cmd.none
      )

    AddRoomRequest ->
      ( { model | newRoom = "", newRoomValid = False }
      , if not model.newRoomValid then Cmd.none
        else
          WebSocket.send model.webSocketUrl
          ( Encode.encode 0
            ( Encode.list
              [ Encode.object
                [ ("type", Encode.string "room")
                , ("op", Encode.string "+")
                , ("key", Encode.string model.newRoom)
                ]
              ]
            )
          )
      )

    RemoveRoomRequest room ->
      ( model
      , WebSocket.send model.webSocketUrl
        ( Encode.encode 0
          ( Encode.list
            [ Encode.object
              [ ("type", Encode.string "room")
              , ("op", Encode.string "-")
              , ("key", Encode.string room)
              ]
            ]
          )
        )
      )

    UpdatedNewTimeSlot newTimeSlot ->
      ( { model
        | newTimeSlot = newTimeSlot
        , newTimeSlotValid = not (newTimeSlot == "" || String.contains "|" newTimeSlot)
        }
      , Cmd.none
      )

    AddTimeSlotRequest ->
      ( { model | newTimeSlot = "" }
      , if not model.newTimeSlotValid then Cmd.none
        else
          WebSocket.send model.webSocketUrl
          ( Encode.encode 0
            ( Encode.list
              [ Encode.object
                [ ("type", Encode.string "timeSlot")
                , ("op", Encode.string "+")
                , ("key", Encode.string model.newTimeSlot)
                ]
              ]
            )
          )
      )

    RemoveTimeSlotRequest timeSlot ->
      ( model
      , WebSocket.send model.webSocketUrl
        ( Encode.encode 0
          ( Encode.list
            [ Encode.object
              [ ("type", Encode.string "timeSlot")
              , ("op", Encode.string "-")
              , ("key", Encode.string timeSlot)
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
          , button [ onClick AddRoomRequest, disabled (not model.newRoomValid) ] [ text "+" ]
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
