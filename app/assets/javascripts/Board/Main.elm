module Board exposing (..)

import Html exposing (..)
import Html.Attributes exposing (style)
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
  { rooms : Set String
  , timeSlots : Set String
  }


type Msg =
  WebSocketMessage String


-- Init
init : (Model, Cmd Msg)
init =
  ( Model Set.empty Set.empty
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


-- Subscription
subscriptions : Model -> Sub Msg
subscriptions model =
  WebSocket.listen "ws://localhost:9000/store" WebSocketMessage


-- View
tableCellStyle : List (String, String)
tableCellStyle =
  [ ( "border", "solid #ddd 1px" ) ]


view : Model -> Html Msg
view model =
  ul []
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
              ( \room -> td [ style tableCellStyle ] [] )
              ( Set.toList model.rooms )
            )
          )
        )
        ( Set.toList model.timeSlots )
      )
    )
  ]


main : Program Never Model Msg
main =
  Html.program
    { init = init
    , update = update
    , subscriptions = subscriptions
    , view = view
    }
