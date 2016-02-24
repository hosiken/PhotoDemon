VERSION 5.00
Begin VB.UserControl pdListBox 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   ClientHeight    =   3600
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   4800
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   9.75
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   HasDC           =   0   'False
   ScaleHeight     =   240
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   320
   ToolboxBitmap   =   "pdListBox.ctx":0000
   Begin PhotoDemon.pdScrollBar vScroll 
      Height          =   1575
      Left            =   2040
      TabIndex        =   1
      Top             =   360
      Visible         =   0   'False
      Width           =   255
      _ExtentX        =   450
      _ExtentY        =   2778
   End
   Begin PhotoDemon.pdListBoxView lbView 
      Height          =   1575
      Left            =   360
      TabIndex        =   0
      Top             =   360
      Width           =   1575
      _ExtentX        =   2778
      _ExtentY        =   2778
   End
End
Attribute VB_Name = "pdListBox"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon List Box control
'Copyright 2015-2016 by Tanner Helland
'Created: 22/December/15
'Last updated: 28/December/15
'Last update: continued work on initial build
'
'Unicode-compatible list box replacement.  Refer to the pdListSupport class and pdListView sub-control for
' additional details; they handle most the heavy lifting for this control.  (This control instance's only job is
' synchronizing the listview and the scrollbar, as necessary.)
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************


Option Explicit

'This control raises much fewer events than a standard ListBox, by design
Public Event Click()

'Because VB focus events are wonky, especially when we use CreateWindow within a UC, this control raises its own
' specialized focus events.  If you need to track focus, use these instead of the default VB functions.
Public Event GotFocusAPI()
Public Event LostFocusAPI()

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'Because this control supports captions, the main interaction area (list + scrollbar) may be shifted slightly downward.
' The usable space of both objects is defined by this rect.
Private m_InteractiveRect As RECTF

'Local list of themable colors.  This list includes all potential colors used by this class, regardless of state change
' or internal control settings.  The list is updated by calling the UpdateColorList function.
' (Note also that this list does not include variants, e.g. "BorderColor" vs "BorderColor_Hovered".  Variant values are
'  automatically calculated by the color management class, and they are retrieved by passing boolean modifiers to that
'  class, rather than treating every imaginable variant as a separate constant.)
Private Enum PDLISTBOX_COLOR_LIST
    [_First] = 0
    PDLB_Background = 0
    [_Last] = 0
    [_Count] = 1
End Enum

'Color retrieval and storage is handled by a dedicated class; this allows us to optimize theme interactions,
' without worrying about the details locally.
Private m_Colors As pdThemeColors

'Caption is handled just like the common control label's caption property.  It is valid at design-time, and any translation,
' if present, will not be processed until run-time.
' IMPORTANT NOTE: only the ENGLISH caption is returned.  I don't have a reason for returning a translated caption (if any),
'                  but I can revisit in the future if it ever becomes relevant.
Public Property Get Caption() As String
Attribute Caption.VB_UserMemId = -518
    Caption = ucSupport.GetCaptionText()
End Property

Public Property Let Caption(ByRef newCaption As String)
    ucSupport.SetCaptionText newCaption
    PropertyChanged "Caption"
End Property

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    lbView.Enabled = newValue
    vScroll.Enabled = newValue
    UserControl.Enabled = newValue
    RedrawBackBuffer
    PropertyChanged "Enabled"
End Property

'Font settings other than size are not supported.  If you want specialized per-item rendering, use an owner-drawn list box
Public Property Get FontSize() As Single
    FontSize = lbView.FontSize
End Property

Public Property Let FontSize(ByVal newSize As Single)
    lbView.FontSize = newSize
    PropertyChanged "FontSize"
End Property

'Font settings other than size are not supported.  If you want specialized per-item rendering, use an owner-drawn list box
Public Property Get FontSizeCaption() As Single
    FontSizeCaption = ucSupport.GetCaptionFontSize()
End Property

Public Property Let FontSizeCaption(ByVal newSize As Single)
    ucSupport.SetCaptionFontSize newSize
    PropertyChanged "FontSizeCaption"
End Property

Public Property Get ContainerHwnd() As Long
    ContainerHwnd = UserControl.ContainerHwnd
End Property

Public Property Get hWnd() As Long
Attribute hWnd.VB_UserMemId = -515
    hWnd = UserControl.hWnd
End Property

'To support high-DPI settings properly, we expose some specialized move+size functions
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

'Listbox-specific functions and subs.  Most of these simply relay the request to the listSupport object, and it will
' raise redraw requests as relevant.
Public Sub AddItem(Optional ByVal srcItemText As String = vbNullString, Optional ByVal itemIndex As Long = -1, Optional ByVal hasTrailingSeparator As Boolean = False, Optional ByVal itemHeight As Long = -1)
    lbView.AddItem srcItemText, itemIndex, hasTrailingSeparator, itemHeight
End Sub

Public Sub Clear()
    lbView.Clear
End Sub

Public Function List(ByVal itemIndex As Long, Optional ByVal returnTranslatedText As Boolean = False) As String
    List = lbView.List(itemIndex, returnTranslatedText)
End Function

Public Function ListCount() As Long
    ListCount = lbView.ListCount
End Function

Public Property Get ListIndex() As Long
    ListIndex = lbView.ListIndex
End Property

Public Property Let ListIndex(ByVal newIndex As Long)
    lbView.ListIndex = newIndex
End Property

Public Function ListIndexByString(ByRef srcString As String, Optional ByVal compareMode As VbCompareMethod = vbBinaryCompare) As Long
    ListIndexByString = lbView.ListIndexByString(srcString, compareMode)
End Function

Public Sub RemoveItem(ByVal itemIndex As Long)
    lbView.RemoveItem itemIndex
End Sub

Private Sub lbView_Click()
    RaiseEvent Click
End Sub

Private Sub lbView_ScrollMaxChanged(ByVal newMax As Long)
    
    Dim changeInVisibility As Boolean: changeInVisibility = False
    If vScroll.Visible <> lbView.ShouldScrollBarBeVisible Then
        vScroll.Visible = lbView.ShouldScrollBarBeVisible
        changeInVisibility = True
    End If
    
    If newMax >= 0 Then vScroll.Max = newMax
    vScroll.LargeChange = lbView.GetDefaultItemHeight
    
    If changeInVisibility Then UpdateControlLayout
    
End Sub

Private Sub lbView_ScrollValueChanged(ByVal newValue As Long)
    If vScroll.Visible Then vScroll.Value = newValue
End Sub

Private Sub ucSupport_GotFocusAPI()
    RaiseEvent GotFocusAPI
End Sub

Private Sub ucSupport_LostFocusAPI()
    RaiseEvent LostFocusAPI
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo Then UpdateControlLayout
    RedrawBackBuffer
End Sub

Private Sub ucSupport_WindowResize(ByVal newWidth As Long, ByVal newHeight As Long)
    UpdateControlLayout
End Sub

Private Sub VScroll_Scroll(ByVal eventIsCritical As Boolean)
    If lbView.ScrollValue <> vScroll.Value Then lbView.ScrollValue = vScroll.Value
End Sub

Private Sub UserControl_Initialize()
    
    'Initialize a master user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd
    ucSupport.RequestCaptionSupport False
    
    'Prep the color manager and load default colors
    Set m_Colors = New pdThemeColors
    Dim colorCount As PDLISTBOX_COLOR_LIST: colorCount = [_Count]
    m_Colors.InitializeColorList "PDListBox", colorCount
    If Not g_IsProgramRunning Then UpdateColorList
    
    'Update the control size parameters at least once
    UpdateControlLayout
    
End Sub

Private Sub UserControl_InitProperties()
    Caption = ""
    FontSize = 10
    FontSizeCaption = 12
End Sub

'At run-time, painting is handled by the support class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    If Not g_IsProgramRunning Then ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)
    With PropBag
        Caption = .ReadProperty("Caption", "")
        FontSize = .ReadProperty("FontSize", 10)
        FontSizeCaption = .ReadProperty("FontSizeCaption", 12)
    End With
End Sub

Private Sub UserControl_Resize()
    If Not g_IsProgramRunning Then ucSupport.RequestRepaint True
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)
    With PropBag
        .WriteProperty "Caption", ucSupport.GetCaptionText, ""
        .WriteProperty "FontSize", lbView.FontSize, 10
        .WriteProperty "FontSizeCaption", ucSupport.GetCaptionFontSize, 12
    End With
End Sub

'Whenever a control property changes that affects control size or layout (including internal changes, like caption adjustments),
' call this function to recalculate the control's internal layout
Private Sub UpdateControlLayout()
    
    'Retrieve DPI-aware control dimensions from the support class
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'Next, determine the positioning of the caption, if present.  (ucSupport.GetCaptionBottom tells us where the
    ' caption text ends vertically.)
    If ucSupport.IsCaptionActive Then
        
        'The list area is placed relative to the caption
        With m_InteractiveRect
            .Left = FixDPI(8)
            .Top = ucSupport.GetCaptionBottom + 2
            .Width = (bWidth - 1) - .Left
            .Height = (bHeight - 1) - .Top
        End With
        
    'If there's no caption, allow the clickable portion to fill the entire control
    Else
        
        With m_InteractiveRect
            .Left = 0
            .Top = 0
            .Width = (bWidth - 1) - .Left
            .Height = (bHeight - 1) - .Top
        End With
        
    End If
    
    'If the scrollbar is visible, we'll position it first.
    If vScroll.Visible Then
        vScroll.SetPositionAndSize (m_InteractiveRect.Width - vScroll.GetWidth), m_InteractiveRect.Top + 1, vScroll.GetWidth, m_InteractiveRect.Height - 2
        lbView.SetPositionAndSize m_InteractiveRect.Left, m_InteractiveRect.Top, vScroll.GetLeft - m_InteractiveRect.Left, m_InteractiveRect.Height
    Else
        lbView.SetPositionAndSize m_InteractiveRect.Left, m_InteractiveRect.Top, m_InteractiveRect.Width, m_InteractiveRect.Height
    End If
            
End Sub

'Primary rendering function.  Note that ucSupport handles a number of rendering duties (like maintaining a back buffer for us).
Private Sub RedrawBackBuffer()
        
    'Request the back buffer DC, and ask the support module to erase any existing rendering for us.
    Dim bufferDC As Long
    bufferDC = ucSupport.GetBackBufferDC(True)
    
    'Paint the final result to the screen, as relevant
    ucSupport.RequestRepaint
    
End Sub

'Before this control does any painting, we need to retrieve relevant colors from PD's primary theming class.  Note that this
' step must also be called if/when PD's visual theme settings change.
Private Sub UpdateColorList()
    With m_Colors
        .LoadThemeColor PDLB_Background, "Background", IDE_WHITE
    End With
End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub UpdateAgainstCurrentTheme()
    UpdateColorList
    If g_IsProgramRunning Then ucSupport.UpdateAgainstThemeAndLanguage
    lbView.UpdateAgainstCurrentTheme
    vScroll.UpdateAgainstCurrentTheme
End Sub

'By design, PD prefers to not use design-time tooltips.  Apply tooltips at run-time, using this function.
' (IMPORTANT NOTE: translations are handled automatically.  Always pass the original English text!)
Public Sub AssignTooltip(ByVal newTooltip As String, Optional ByVal newTooltipTitle As String, Optional ByVal newTooltipIcon As TT_ICON_TYPE = TTI_NONE)
    ucSupport.AssignTooltip UserControl.ContainerHwnd, newTooltip, newTooltipTitle, newTooltipIcon
End Sub
