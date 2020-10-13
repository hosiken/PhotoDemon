VERSION 5.00
Begin VB.UserControl pdRandomizeUI 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   ClientHeight    =   420
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   6000
   DrawStyle       =   5  'Transparent
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   HasDC           =   0   'False
   MousePointer    =   99  'Custom
   ScaleHeight     =   28
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   400
   ToolboxBitmap   =   "pdRandomizeUI.ctx":0000
   Begin PhotoDemon.pdTextBox txtSeed 
      Height          =   375
      Left            =   120
      TabIndex        =   1
      Top             =   360
      Width           =   5175
      _ExtentX        =   9128
      _ExtentY        =   661
   End
   Begin PhotoDemon.pdButtonToolbox cmdRandomize 
      Height          =   375
      Left            =   5400
      TabIndex        =   0
      Top             =   360
      Width           =   375
      _ExtentX        =   661
      _ExtentY        =   661
      AutoToggle      =   -1  'True
   End
End
Attribute VB_Name = "pdRandomizeUI"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Random Number UI control
'Copyright 2018-2020 by Tanner Helland
'Created: 02/April/18
'Last updated: 02/April/18
'Last update: initial build
'
'Software like PhotoDemon requires a lot of UI elements.  Ideally, every setting should be adjustable by at least
' two mechanisms: direct text entry, and some kind of slider or scroll bar, which allows for a quick method to
' make both large and small adjustments to a given parameter.
'
'Historically, I accomplished this by providing a scroll bar and text box for every parameter in the program.
' This got the job done, but it had a number of limitations - such as requiring an enormous amount of time if
' changes ever needed to be made, and custom code being required in every form to handle text / scroll syncing.
'
'In April 2013, it was brought to my attention that some locales (e.g. Italy) use a comma instead of a decimal
' for float values.  Rather than go through and add custom support for this to every damn form, I finally did
' the smart thing and built a custom text/scroll user control.  This effectively replaces all other text/scroll
' combos in the program.
'
'In June 2014, I finally did what I should have done long ago and swapped out the scroll bar for a custom-drawn
' slider.  That update also added support for some new features (like custom images on the background-track),
' while helping prepare PD for full theming support.
'
'Anyway, as of today, this control handles the following things automatically:
' 1) Syncing of text and scroll/slide values
' 2) Validation of text entries, including a function for external validation requests
' 3) Locale handling (like the aforementioned comma/decimal replacement in some countries)
' 4) A single "Change" event that fires for either scroll or text changes, and only if a text change is valid
' 5) Support for integer or floating-point values via the "SigDigits" property
' 6) Several different drawing modes, including support for 2- or 3-point gradients
' 7) Self-captioning, to remove the need for a redundant label control next to this one
'
'Unless otherwise noted, all source code in this file is shared under a simplified BSD license.
' Full license details are available in the LICENSE.md file, or at https://photodemon.org/license/
'
'***************************************************************************

Option Explicit

'Change vs FinalChange: change is fired whenever the scroller value changes at all (e.g. during every
' mouse movement); FinalChange is fired only when a mouse or key is released.  If the slider controls a
' particularly time-consuming operation, it may be preferable to lean on FinalChange instead of Change,
' but note the caveat that FinalChange *only* triggers on MouseUp/KeyUp - *not* on external .Value changes
' - so you may still need to handle the regular Change event, if you are externally setting values.
' This oddity is necessary because otherwise, the spinner and slider controls constantly trigger each
' other's .Value properties, causing endless FinalChange triggers.
Public Event Change()
Public Event FinalChange()
Public Event ResetClick()

'Because VB focus events are wonky, especially when we use CreateWindow within a UC, this control raises its own
' specialized focus events.  If you need to track focus, use these instead of the default VB functions.
Public Event GotFocusAPI()
Public Event LostFocusAPI()

'If this is an owner-drawn slider, the slider will raise events when it needs an updated track image.
' (This event is irrelevant for normal sliders.)
Public Event RenderTrackImage(ByRef dstDIB As pdDIB, ByVal leftBoundary As Single, ByVal rightBoundary As Single)

'Current value, stored as a string.  (Any character is allowed, but when the "reset" button is used, only alpha-numeric
' English characters will be randomly generated.)
Private m_Value As String

'If the text box initiates a value change, we must track it so as to not overwrite the user's entry mid-typing
Private m_textBoxInitiated As Boolean

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'Tracks whether the control (any component) has focus.  This is helpful as this control contains a number of child controls,
' and we want to raise focus events only if *none of our children* have focus (or alternatively, if *one of our children*
' gains focus).
Private m_LastFocusState As Boolean

'Used to prevent recursive redraws
Private m_InternalResizeActive As Boolean

Public Function GetControlType() As PD_ControlType
    GetControlType = pdct_RandomizeUI
End Function

Public Function GetControlName() As String
    GetControlName = UserControl.Extender.Name
End Function

'Caption is handled just like the common control label's caption property.  It is valid at design-time, and any translation,
' if present, will not be processed until run-time.
' IMPORTANT NOTE: only the ENGLISH caption is returned.  I don't have a reason for returning a translated caption (if any),
'                  but I can revisit in the future if it ever becomes relevant.
Public Property Get Caption() As String
Attribute Caption.VB_UserMemId = -518
    Caption = ucSupport.GetCaptionText
End Property

Public Property Let Caption(ByRef newCaption As String)
    ucSupport.SetCaptionText newCaption
    PropertyChanged "Caption"
End Property

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    txtSeed.Enabled = newValue
    cmdRandomize.Enabled = newValue
    UserControl.Enabled = newValue
    PropertyChanged "Enabled"
End Property

Public Property Get FontSizeCaption() As Single
    FontSizeCaption = ucSupport.GetCaptionFontSize
End Property

Public Property Let FontSizeCaption(ByVal newSize As Single)
    ucSupport.SetCaptionFontSize newSize
    PropertyChanged "FontSizeCaption"
End Property

Public Property Get FontSizeEdit() As Single
    FontSizeEdit = txtSeed.FontSize
End Property

Public Property Let FontSizeEdit(ByVal newSize As Single)
    If (newSize <> txtSeed.FontSize) Then
        txtSeed.FontSize = newSize
        PropertyChanged "FontSizeEdit"
    End If
End Property

Public Property Get HasFocus() As Boolean
    HasFocus = ucSupport.DoIHaveFocus() Or txtSeed.HasFocus() Or cmdRandomize.HasFocus()
End Property

Public Property Get hWnd() As Long
    hWnd = UserControl.hWnd
End Property

'The control's current seed is simply a string value; pdRandomize should be used to convert this to a usable
' numeric representation.
Public Property Get Value() As String
Attribute Value.VB_UserMemId = 0
    Value = m_Value
End Property

Public Property Let Value(ByRef newValue As String)
    
    'Don't make any changes unless the new value deviates from the existing one
    If (newValue <> m_Value) Then
        m_Value = newValue
        If (Not m_textBoxInitiated) Then txtSeed.Text = newValue
        If Me.Enabled Then RaiseEvent Change
        PropertyChanged "Value"
    End If
    
End Property

'If an external function wants to trigger a randomize event (just like clicking the "randomize" button), call this function.
Public Sub Randomize()

    'The Unicode ranges allowed by the random number generator include: 48-57, 65-90, 97-122.
    ' These were chosen arbitrarily to include numbers and upper/lowercase letters.  (Users in other locales
    ' may want a different system, but I'm not sure how to reasonably provide this at present - sorry!)
    Dim cRandom As pdRandomize
    Set cRandom = New pdRandomize
    cRandom.SetSeed_AutomaticAndRandom
    cRandom.SetRndIntegerBounds 48, 122
    
    'We are going to assemble a random n-character string from the allowed characters specified above.
    Const SEED_LENGTH As Long = 35
    Dim cString As pdString
    Set cString = New pdString
    
    Dim i As Long, chrCode As Long
    
    For i = 1 To SEED_LENGTH
        
        If ((i And 3) <> 0) Then
        
            chrCode = cRandom.GetRandomInt_WH()
            
            Do While ((chrCode > 57) And (chrCode < 65)) Or ((chrCode > 90) And (chrCode < 97))
                chrCode = cRandom.GetRandomInt_WH()
            Loop
            
            cString.Append ChrW$(chrCode)
            
        Else
            cString.Append "-"
        End If
        
    Next i
    
    Me.Value = cString.ToString()
    
End Sub

Public Sub Reset()
    Me.Value = vbNullString
End Sub

'To support high-DPI settings properly, we expose specialized move+size functions
Public Function GetLeft() As Long
    GetLeft = ucSupport.GetControlLeft
End Function

Public Sub SetLeft(ByVal newLeft As Long)
    ucSupport.RequestNewPosition newLeft, , True
End Sub

Public Function GetTop() As Long
    GetTop = ucSupport.GetControlTop
End Function

Public Sub SetTop(ByVal newTop As Long)
    ucSupport.RequestNewPosition , newTop, True
End Sub

Public Function GetWidth() As Long
    GetWidth = ucSupport.GetControlWidth
End Function

Public Sub SetWidth(ByVal newWidth As Long)
    ucSupport.RequestNewSize newWidth, , True
End Sub

Public Function GetHeight() As Long
    GetHeight = ucSupport.GetControlHeight
End Function

Public Sub SetHeight(ByVal newHeight As Long)
    ucSupport.RequestNewSize , newHeight, True
End Sub

Public Sub SetPositionAndSize(ByVal newLeft As Long, ByVal newTop As Long, ByVal newWidth As Long, ByVal newHeight As Long)
    ucSupport.RequestFullMove newLeft, newTop, newWidth, newHeight, True
End Sub

'The randomize button generates a random alphanumeric string
Private Sub cmdRandomize_Click(ByVal Shift As ShiftConstants)
    Me.Randomize
End Sub

Private Sub cmdRandomize_GotFocusAPI()
    EvaluateFocusCount
End Sub

Private Sub cmdRandomize_LostFocusAPI()
    EvaluateFocusCount
End Sub

Private Sub txtSeed_Change()
    m_textBoxInitiated = True
    If (Me.Value <> txtSeed.Text) Then Me.Value = txtSeed.Text
    m_textBoxInitiated = False
End Sub

Private Sub txtSeed_GotFocusAPI()
    EvaluateFocusCount
End Sub

Private Sub txtSeed_LostFocusAPI()
    EvaluateFocusCount
End Sub

Private Sub txtSeed_Resize()
    UpdateControlLayout
End Sub

Private Sub ucSupport_GotFocusAPI()
    EvaluateFocusCount
End Sub

Private Sub ucSupport_KeyDownSystem(ByVal Shift As ShiftConstants, ByVal whichSysKey As PD_NavigationKey, markEventHandled As Boolean)
    
    'Enter/Esc get reported directly to the system key handler.  Note that we track the return, because TRUE
    ' means the key was successfully forwarded to the relevant handler.  (If FALSE is returned, no control
    ' accepted the keypress, meaning we should forward the event down the line.)
    markEventHandled = NavKey.NotifyNavKeypress(Me, whichSysKey, Shift)
    
End Sub

Private Sub ucSupport_LostFocusAPI()
    EvaluateFocusCount
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo Then UpdateControlLayout Else ucSupport.RequestRepaint True
End Sub

Private Sub ucSupport_WindowResize(ByVal newWidth As Long, ByVal newHeight As Long)
    If (Not m_InternalResizeActive) Then UpdateControlLayout
End Sub

Private Sub UserControl_Initialize()
    
    'Initialize a master user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd, False
    ucSupport.RequestExtraFunctionality True, , , False
    ucSupport.RequestCaptionSupport False
        
End Sub

'Initialize control properties for the first time
Private Sub UserControl_InitProperties()
    Caption = vbNullString
    FontSizeEdit = 10
    FontSizeCaption = 12
    Value = vbNullString
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)

    With PropBag
        Caption = .ReadProperty("Caption", vbNullString)
        FontSizeCaption = .ReadProperty("FontSizeCaption", 12)
        FontSizeEdit = .ReadProperty("FontSizeEdit", 10)
        Value = .ReadProperty("Value", vbNullString)
    End With
    
End Sub

'At run-time, painting is handled by PD's pdWindowPainter class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_Resize()
    If (Not PDMain.IsProgramRunning()) Then ucSupport.NotifyIDEResize UserControl.Width, UserControl.Height
End Sub

Private Sub UserControl_Show()
    UpdateControlLayout
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)

    With PropBag
        .WriteProperty "Caption", Me.Caption, vbNullString
        .WriteProperty "FontSizeCaption", Me.FontSizeCaption, 12
        .WriteProperty "FontSizeEdit", Me.FontSizeEdit, 10
        .WriteProperty "Value", Me.Value, vbNullString
    End With
    
End Sub

'When the control is resized, the caption is changed, or font sizes for either the caption or text up/down are modified,
' this function should be called.  It controls the physical positioning of various control sub-elements
' (specifically, the caption area, the slider area, and the text up/down area).
Private Sub UpdateControlLayout()
    
    If m_InternalResizeActive Then Exit Sub
    
    'Set a control-level flag to prevent recursive redraws
    m_InternalResizeActive = True
    
    'NB: order of operations is important in this function.  We first calculate all new size/position values.
    ' When all new values are known, we apply them in a single fell swoop to avoid the need for costly redraws.
    
    'The first size consideration is accounting for the presence of a control caption.
    Dim captionHeight As Long, editLeft As Long
    If ucSupport.IsCaptionActive Then
        captionHeight = ucSupport.GetCaptionHeight + Interface.FixDPI(4)
        editLeft = Interface.FixDPI(8)
    Else
        captionHeight = 0
        editLeft = 0
    End If
    
    Dim newControlHeight As Long
    newControlHeight = captionHeight + txtSeed.GetHeight + Interface.FixDPI(2)
    
    'Apply the new height to this UC instance, as necessary
    If (ucSupport.GetControlHeight <> newControlHeight) Then ucSupport.RequestNewSize , newControlHeight
    
    'Next, we need to position the edit box and randomize/reset buttons relative to the caption (if any).
    txtSeed.SetPositionAndSize editLeft, captionHeight, ucSupport.GetControlWidth - (Interface.FixDPI(8) + editLeft) - (txtSeed.GetHeight + Interface.FixDPI(2)), txtSeed.GetHeight
    
    Dim cmdRandomizeSize As Long
    cmdRandomizeSize = txtSeed.GetHeight + Interface.FixDPI(4)
    cmdRandomize.SetPositionAndSize txtSeed.GetLeft + txtSeed.GetWidth + Interface.FixDPI(4), txtSeed.GetTop - Interface.FixDPI(2), cmdRandomizeSize, cmdRandomizeSize
    
    ucSupport.RequestRepaint True
    m_InternalResizeActive = False
    
End Sub

'After a component of this control gets or loses focus, it needs to call this function.  This function is responsible for raising
' Got/LostFocusAPI events, which are important as an API text box is part of this control.
Private Sub EvaluateFocusCount()

    If (Not m_LastFocusState) And Me.HasFocus() Then
        m_LastFocusState = True
        RaiseEvent GotFocusAPI
    ElseIf m_LastFocusState And (Not Me.HasFocus()) Then
        m_LastFocusState = False
        RaiseEvent LostFocusAPI
    End If

End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub UpdateAgainstCurrentTheme(Optional ByVal hostFormhWnd As Long = 0)
    
    If ucSupport.ThemeUpdateRequired Then
        
        cmdRandomize.AssignImage "generic_random", , Interface.FixDPI(20), Interface.FixDPI(20)
        
        txtSeed.UpdateAgainstCurrentTheme
        cmdRandomize.UpdateAgainstCurrentTheme
        cmdRandomize.AssignTooltip "Generate a new random number seed."
        
        If PDMain.IsProgramRunning() Then NavKey.NotifyControlLoad Me, hostFormhWnd, False
        If PDMain.IsProgramRunning() Then ucSupport.UpdateAgainstThemeAndLanguage
        
    End If
    
End Sub

'Due to complex interactions between user controls and PD's translation engine, tooltips require this dedicated function.
' (IMPORTANT NOTE: the tooltip class will handle translations automatically.  Always pass the original English text!)
Public Sub AssignTooltip(ByRef newTooltip As String, Optional ByRef newTooltipTitle As String = vbNullString, Optional ByVal raiseTipsImmediately As Boolean = False)
    txtSeed.AssignTooltip newTooltip, newTooltipTitle
    cmdRandomize.AssignTooltip newTooltip, newTooltipTitle
End Sub
