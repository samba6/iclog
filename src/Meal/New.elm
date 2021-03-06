module Meal.New
    exposing
        ( Model
        , Msg
        , update
        , view
        , subscriptions
        , init
        , queryStore
        )

import Html exposing (Html, Attribute)
import Html.Attributes as Attr
import Html.Events exposing (onSubmit, onClick)
import Form exposing (Form, FieldState)
import Form.Field as Field exposing (Field)
import Form.Input as Input exposing (Input)
import Form.Validate as Validate exposing (Validation, withCustomError)
import Date exposing (Date)
import Utils
    exposing
        ( (=>)
        , nonEmpty
        , formatDateForForm
        , formatDateISOWithTimeZone
        , unSubmit
        , unknownServerError
        , decodeErrorMsg
        , focusEl
        , getDateNow
        )
import DateTimePicker
import DateTimePicker.Config as DateTimePickerConfig
    exposing
        ( DatePickerConfig
        , defaultDateTimePickerConfig
        , TimePickerConfig
        )
import Meal.Types exposing (MealId, fromMealId)
import Store exposing (Store, TimeZoneOffset)
import Css
import Views.Nav exposing (nav)
import Router
import Views.FormUtils as FormUtils
import Meal.Channel as Channel exposing (ChannelState)
import Phoenix
import Views.CreationSuccessAlert as CreationSuccessAlert
import Comment exposing (CommentValue)
import Views.Util exposing (cardTitle)


type alias Model =
    { form : Form String FormValue
    , serverError : Maybe String
    , submitting : Bool
    , creatingComment : Bool
    , selectedDate : Maybe Date
    , datePickerState : DateTimePicker.State
    , newMeal : Maybe MealId
    }


type alias FormValue =
    { meal : String
    , comment : CommentValue
    }


initialFields : List ( String, Field )
initialFields =
    []


defaults : Model
defaults =
    { form = Form.initial initialFields <| validate False
    , serverError = Nothing
    , submitting = False
    , creatingComment = False
    , newMeal = Nothing
    , selectedDate = Nothing
    , datePickerState = DateTimePicker.initialState
    }


init : ( Model, Cmd Msg )
init =
    defaults
        ! [ focusEl "new-meal-input" NoOp
          , DateTimePicker.initialCmd
                DatePickerInitialMsg
                DateTimePicker.initialState
          , getDateNow Today
          ]


type alias QueryStore =
    { websocketUrl : Maybe String
    , tzOffset : TimeZoneOffset
    }


queryStore : Store -> QueryStore
queryStore store =
    { websocketUrl = Store.getWebsocketUrl store
    , tzOffset = Store.getTimeZoneOffset store
    }


type Msg
    = NoOp ()
    | FormMsg Form.Msg
    | DatePickerChanged DateTimePicker.State (Maybe Date)
    | DatePickerInitialMsg DateTimePicker.State (Maybe Date)
    | ResetForm
    | SubmitForm
    | Today Date
    | ToggleCommentForm
    | ChannelMsg ChannelState


update : Msg -> Model -> QueryStore -> ( Model, Cmd Msg )
update msg ({ form } as model) store =
    case msg of
        Today today ->
            { model
                | selectedDate = Just today
            }
                ! []

        FormMsg formMsg ->
            revalidateForm formMsg model
                => Cmd.none

        DatePickerInitialMsg datePickerState _ ->
            { model
                | datePickerState = datePickerState
            }
                ! []

        DatePickerChanged datePickerState maybeDate ->
            { model
                | datePickerState = datePickerState
                , selectedDate = maybeDate
            }
                ! []

        ToggleCommentForm ->
            let
                ( model_, cmd ) =
                    Comment.toggleCommentForm
                        model
                        revalidateForm
                        commentControlId
                        NoOp
            in
                model_ ! [ cmd ]

        ResetForm ->
            resetForm model ! [ getDateNow Today ]

        SubmitForm ->
            let
                newForm =
                    Form.update
                        (validate model.creatingComment)
                        Form.Submit
                        form

                newModel =
                    { model | form = newForm }
            in
                case ( Form.getOutput newForm, model.selectedDate, store.websocketUrl ) of
                    ( Just { meal, comment }, Just date, Just websocketUrl ) ->
                        let
                            time =
                                formatDateISOWithTimeZone
                                    (Store.toTimeZoneVal
                                        store.tzOffset
                                    )
                                    date

                            params =
                                if model.creatingComment then
                                    { meal = meal
                                    , comment = Just comment
                                    , time = time
                                    }
                                else
                                    { meal = meal
                                    , comment = Nothing
                                    , time = time
                                    }

                            cmd =
                                Channel.create params
                                    |> Phoenix.push websocketUrl
                                    |> Cmd.map ChannelMsg
                        in
                            { newModel
                                | submitting = True
                            }
                                ! [ cmd ]

                    _ ->
                        model ! []

        ChannelMsg channelState ->
            case channelState of
                Channel.CreateSucceeds mealId_ ->
                    case mealId_ of
                        Ok mealId ->
                            { defaults | newMeal = Just mealId }
                                ! [ getDateNow Today ]

                        Err err ->
                            let
                                x =
                                    Debug.log (decodeErrorMsg msg) err
                            in
                                (unSubmit model
                                    |> unknownServerError
                                )
                                    ! []

                Channel.CreateFails val ->
                    let
                        model_ =
                            unSubmit model
                                |> unknownServerError

                        mesg =
                            "Channel.CreateFails with: "

                        x =
                            Debug.log ("\n\n ->" ++ mesg) val
                    in
                        model_ ! []

                _ ->
                    model ! []

        NoOp _ ->
            ( model, Cmd.none )


revalidateForm : Form.Msg -> Model -> Model
revalidateForm formMsg model =
    { model
        | form =
            Form.update
                (validate model.creatingComment)
                formMsg
                model.form
        , serverError = Nothing
    }


resetForm : Model -> Model
resetForm model =
    { model
        | form = Form.initial initialFields <| validate False
        , serverError = Nothing
        , submitting = False
        , creatingComment = False
        , newMeal = Nothing
        , datePickerState = DateTimePicker.initialState
    }



-- VIEW


commentControlId : String
commentControlId =
    "new-meal-comment"


view : Model -> Html Msg
view ({ form, serverError, submitting } as model) =
    let
        ( mealControl, mealInvalid ) =
            formControlMeal model

        ( commentControl, commentInvalid, _ ) =
            Comment.formControl4
                model.form
                commentControlId
                FormMsg
                model.creatingComment

        ( timeControl, timeInvalid ) =
            formControlTime model

        label_ =
            case submitting of
                True ->
                    "Submitting.."

                False ->
                    "Submit"

        disableSubmitBtn =
            timeInvalid
                || mealInvalid
                || commentInvalid
                || ([] /= Form.getErrors form)
                || (model.submitting == True)

        disableResetBtn =
            (model.submitting == True)
    in
        Html.div []
            [ nav
                (Just Router.MealNew)
                Router.MealList
                Router.MealNew
                "meal"
            , CreationSuccessAlert.view
                { id = (Maybe.map fromMealId model.newMeal)
                , route = Just Router.MealDetail
                , label = "meal"
                , dismissMsg = Nothing
                }
            , Html.div
                [ Attr.class "row" ]
                [ Html.div
                    [ Attr.class
                        "col-12 col-sm-10 offset-sm-1 col-md-8 offset-md-2"
                    ]
                    [ Html.div
                        [ Attr.class "card" ]
                        [ Html.form
                            [ Attr.class "card-body new-meal-form"
                            , Attr.novalidate True
                            , Attr.id "new-meal-form"
                            , onSubmit SubmitForm
                            ]
                            [ FormUtils.textualErrorBox model.serverError
                            , cardTitle "New meal"
                            , Html.div
                                [ Attr.class "new-meal-form-controls"
                                , Attr.id "new-meal-form-controls"
                                , styles [ Css.marginBottom (Css.rem 1) ]
                                ]
                                [ mealControl
                                , timeControl
                                , Comment.view
                                    commentControl
                                    model.creatingComment
                                    ToggleCommentForm
                                ]
                            , FormUtils.formBtns
                                [ Attr.disabled disableSubmitBtn
                                , Attr.name "new-meal-submit-btn"
                                ]
                                [ Attr.disabled disableResetBtn
                                , Attr.name "new-meal-reset-btn"
                                ]
                                label_
                                ResetForm
                            ]
                        ]
                    ]
                ]
            ]


formControlMeal : Model -> ( Html Msg, Bool )
formControlMeal { form } =
    let
        mealField =
            Form.getFieldAsString "meal" form

        ( isValid, isInvalid ) =
            FormUtils.controlValidityState mealField

        mealFieldValue =
            Maybe.withDefault
                ""
                mealField.value
    in
        (FormUtils.formGrp
            Input.textArea
            mealField
            [ Attr.placeholder "Meal"
            , Attr.name "new-meal-input"
            , Attr.id "new-meal-input"
            , Attr.value mealFieldValue
            , Attr.class "autoExpand"
            ]
            { errorId = "new-meal-input-error-id"
            , errors = Nothing
            }
            FormMsg
        )
            => isInvalid


formControlTime : Model -> ( Html Msg, Bool )
formControlTime model =
    let
        ( isValid, isInvalid, error ) =
            case model.selectedDate of
                Nothing ->
                    ( False
                    , True
                    , Just "Select a date from the datepicker."
                    )

                Just _ ->
                    ( True, False, Nothing )

        dateInput =
            DateTimePicker.dateTimePickerWithConfig
                config
                [ Attr.classList
                    [ ( "form-control", True )
                    , ( "is-invalid", isInvalid )
                    , ( "is-valid", isValid )
                    ]
                , Attr.id "new-meal-time"
                , Attr.name "new-meal-time"
                ]
                model.datePickerState
                model.selectedDate

        config : DateTimePickerConfig.Config (DatePickerConfig TimePickerConfig) Msg
        config =
            let
                defaultDateTimeConfig =
                    defaultDateTimePickerConfig DatePickerChanged

                i18n =
                    defaultDateTimeConfig.i18n

                inputFormat =
                    i18n.inputFormat

                i18n_ =
                    { i18n
                        | inputFormat =
                            { inputFormat
                                | inputFormatter = formatDateForForm
                            }
                    }
            in
                { defaultDateTimeConfig
                    | timePickerType = DateTimePickerConfig.Digital
                    , i18n = i18n_
                }
    in
        Html.div
            [ Attr.id "new-meal-time-input-grpup" ]
            [ dateInput
            , FormUtils.textualError
                { errors = error
                , errorId = "new-meal-time-error-id"
                }
            ]
            => isInvalid


styles : List Css.Style -> Attribute msg
styles =
    Css.asPairs >> Attr.style



-- form validation


validate : Bool -> Validation String FormValue
validate creatingComment =
    Validate.succeed FormValue
        |> Validate.andMap
            (Validate.field
                "meal"
                (nonEmpty 3
                    |> withCustomError
                        "Meal must be at least 3 characters."
                )
            )
        |> Validate.andMap
            (Validate.field "comment" <| Comment.validate creatingComment)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none
