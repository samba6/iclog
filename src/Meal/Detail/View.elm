module Meal.Detail.View exposing (view)

import Html exposing (Html, Attribute)
import Html.Attributes as Attr
import Html.Events exposing (onClick, onSubmit)
import Views.Nav exposing (nav)
import Router
import Views.FormUtils as FormUtils
import Form.Input as Input exposing (Input)
import Css
import Views.CreationSuccessAlert as CreationSuccessAlert
import Meal.Detail.App
    exposing
        ( Model
        , Msg(..)
        , Viewing(..)
        , FormValue
        , commentControlId
        )
import Meal.Types
    exposing
        ( MealWithComments
        , fromMealId
        )
import Utils exposing (formatDateForForm, (=>))
import Form exposing (Form)
import Views.Util exposing (cardTitle, formControlDateTimePicker)
import Comment exposing (Comment, CommentValue, commentsView)


view : Model -> Html Msg
view ({ meal, viewing } as model) =
    let
        mainView =
            case meal of
                Nothing ->
                    Html.text ""

                Just meal_ ->
                    case viewing of
                        ViewingDetail ->
                            viewDetail meal_ model

                        ViewingEdit ->
                            viewEdit meal_ model
    in
        Html.div [ Attr.id "meal-detail" ]
            [ nav Nothing Router.MealList Router.MealNew "meal"
            , mainView
            ]


viewDetail : MealWithComments -> Model -> Html Msg
viewDetail ({ meal, time, comments } as meal_) model =
    let
        alertId =
            if model.editSuccess == True then
                Just <| fromMealId meal_.id
            else
                Nothing
    in
        Html.div
            [ Attr.class "card" ]
            [ Html.div
                [ Attr.class "card-body" ]
                [ cardTitle "Details"
                , CreationSuccessAlert.view
                    { id = alertId
                    , route = Nothing
                    , label = "meal"
                    , dismissMsg = Just DismissEditSuccessInfo
                    }
                , Html.p
                    [ Attr.class "card-text" ]
                    [ Html.text meal ]
                , Html.div
                    [ Attr.class "card-link"
                    , styles
                        [ Css.displayFlex
                        , Css.flexDirection Css.rowReverse
                        ]
                    ]
                    [ Html.i
                        [ Attr.class "fa fa-pencil-square-o"
                        , styles
                            [ Css.cursor Css.pointer
                            , Css.maxWidth (Css.px 10)
                            , Css.marginRight (Css.px 5)
                            ]
                        , onClick <| ChangeView ViewingEdit
                        , Attr.id "detail-meal-show-edit-display"
                        ]
                        []
                    , case model.commentForm of
                        Just _ ->
                            Html.div [] []

                        Nothing ->
                            Comment.addCommentToggle
                                ToggleAddComment
                                "detail-meal-add-comment-toggle"
                    ]
                , Html.div
                    [ styles [ Css.marginTop (Css.px 10) ] ]
                    [ viewCommentForm model.commentForm ]
                , commentsView comments
                ]
            , Html.div
                [ Attr.class "card-footer text-muted" ]
                [ Html.text <| formatDateForForm time ]
            ]


viewCommentForm : Maybe (Form String CommentValue) -> Html Msg
viewCommentForm maybeForm =
    case maybeForm of
        Nothing ->
            Html.text ""

        Just form_ ->
            let
                ( dom, _, valid ) =
                    Comment.formControl3
                        "text"
                        form_
                        "meal-add-comment"
                        CommentFormMsg

                actionStyles =
                    [ Css.cursor Css.pointer
                    ]

                submitView =
                    if valid == True then
                        Html.i
                            [ Attr.class "fa fa-check"
                            , Attr.attribute "aria-hidden" "true"
                            , Attr.id "meal-detail-add-comment-submit"
                            , onClick SubmitCommentForm
                            , styles
                                (actionStyles
                                    ++ [ Css.color (Css.rgb 40 167 69)
                                       , Css.padding (Css.px 0)
                                       , Css.marginTop (Css.rem 1)
                                       ]
                                )
                            ]
                            []
                    else
                        Html.div [] []
            in
                Html.div
                    [ Attr.class "adding-new-comment-only"
                    , styles [ Css.displayFlex ]
                    ]
                    [ Html.div
                        [ styles
                            [ Css.displayFlex
                            , Css.flexDirection Css.column
                            , Css.marginRight (Css.px 5)
                            ]
                        ]
                        [ Html.i
                            [ Attr.class "fa fa-ban"
                            , Attr.attribute "aria-hidden" "true"
                            , Attr.id "meal-detail-add-comment-dismiss"
                            , styles
                                (actionStyles
                                    ++ [ Css.padding (Css.px 0)
                                       , Css.color (Css.rgb 255 59 48)
                                       , Css.marginTop (Css.rem 0.3)
                                       ]
                                )
                            , onClick ToggleAddComment
                            ]
                            []
                        , submitView
                        ]
                    , Html.div
                        [ styles [ Css.flex (Css.int 1) ] ]
                        [ dom ]
                    ]


viewEdit : MealWithComments -> Model -> Html Msg
viewEdit ({ meal, time, comments } as meal_) ({ viewing } as model) =
    let
        ( mealControl, mealInvalid ) =
            formControlMeal meal model

        ( timeControl, _, timeInvalid, _ ) =
            formControlDateTimePicker
                model.selectedDate
                DatePickerChanged
                model.datePickerState
                "detail-meal-edit-time"

        ( commentControl, commentInvalid, commentValid ) =
            Comment.formControl4
                model.form
                commentControlId
                FormMsg
                model.creatingComment

        label_ =
            case model.submitting of
                True ->
                    "Submitting..."

                False ->
                    "Submit"

        mealChanged =
            case mealFromForm model.form of
                Nothing ->
                    True

                Just aMeal ->
                    meal /= aMeal

        timeChanged =
            Maybe.map formatDateForForm model.selectedDate
                /= (Just <| formatDateForForm time)

        disableSubmitBtn =
            (model.submitting == True)
                || timeInvalid
                || mealInvalid
                || commentInvalid
                || ([] /= Form.getErrors model.form)
                || (mealChanged
                        == False
                        && timeChanged
                        == False
                        && commentValid
                        == False
                   )

        disableResetBtn =
            model.submitting == True
    in
        Html.div
            [ Attr.class "row" ]
            [ Html.div
                [ Attr.class
                    "col-12 col-sm-10 offset-sm-1 col-md-8 offset-md-2"
                ]
                [ Html.div
                    [ Attr.class "card" ]
                    [ Html.form
                        [ Attr.class "card-body edit-meal-form"
                        , Attr.novalidate True
                        , Attr.id "edit-meal-form"
                        , onSubmit <| SubmitForm meal_
                        ]
                        [ cardTitle "Edit meal"
                        , Html.div
                            [ Attr.class "card-link"
                            , styles
                                [ Css.displayFlex
                                , Css.flexDirection Css.rowReverse
                                , Css.marginBottom (Css.px 10)
                                ]
                            ]
                            [ Html.i
                                [ Attr.class "fa fa-eye"
                                , styles [ Css.cursor Css.pointer ]
                                , onClick <| ChangeView ViewingDetail
                                , styles
                                    [ Css.maxWidth (Css.px 0)
                                    , Css.marginRight (Css.px 8)
                                    ]
                                , Attr.id "detail-meal-show-detail-display"
                                ]
                                []
                            , (if model.creatingComment == True then
                                Html.text ""
                               else
                                Html.i
                                    [ Attr.class "fa fa-comment"
                                    , styles [ Css.cursor Css.pointer ]
                                    , onClick ToggleCommentForm
                                    , styles
                                        [ Css.maxWidth (Css.px 0)
                                        , Css.marginRight (Css.px 10)
                                        ]
                                    , Attr.id
                                        "comment-edit-view-helper-reveal-composite-comment-id"
                                    ]
                                    []
                              )
                            ]
                        , Html.div
                            [ Attr.class "edit-meal-form-controls"
                            , Attr.id "edit-meal-form-controls"
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
                            , Attr.name "edit-meal-submit-btn"
                            , Attr.id "edit-meal-submit-btn"
                            ]
                            [ Attr.disabled disableResetBtn
                            , Attr.name "edit-meal-reset-btn"
                            ]
                            label_
                            ResetForm
                        ]
                    ]
                ]
            ]


formControlMeal : String -> Model -> ( Html Msg, Bool )
formControlMeal meal { form } =
    let
        mealField =
            Form.getFieldAsString "meal" form

        ( isValid, isInvalid ) =
            FormUtils.controlValidityState mealField

        mealFieldValue =
            Maybe.withDefault
                meal
                mealField.value
    in
        (FormUtils.formGrp
            Input.textArea
            mealField
            [ Attr.placeholder "Meal"
            , Attr.name "edit-meal-input"
            , Attr.id "edit-meal-input"
            , Attr.value mealFieldValue
            , Attr.class "autoExpand"
            ]
            { errorId = "edit-meal-input-error-id"
            , errors = Nothing
            }
            FormMsg
        )
            => isInvalid


mealFromForm : Form String FormValue -> Maybe String
mealFromForm form_ =
    Form.getOutput form_ |> Maybe.map .meal


styles : List Css.Style -> Attribute msg
styles =
    Css.asPairs >> Attr.style
