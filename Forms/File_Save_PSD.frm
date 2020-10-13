VERSION 5.00
Begin VB.Form dialog_ExportPSD 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   ClientHeight    =   6585
   ClientLeft      =   45
   ClientTop       =   390
   ClientWidth     =   12630
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
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   439
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   842
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5835
      Width           =   12630
      _ExtentX        =   22278
      _ExtentY        =   1323
      DontAutoUnloadParent=   -1  'True
   End
   Begin PhotoDemon.pdFxPreviewCtl pdFxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
   End
   Begin PhotoDemon.pdButtonStrip btsCategory 
      Height          =   615
      Left            =   5880
      TabIndex        =   2
      Top             =   120
      Width           =   6615
      _ExtentX        =   11668
      _ExtentY        =   1085
      FontSize        =   11
   End
   Begin PhotoDemon.pdContainer picContainer 
      Height          =   4815
      Index           =   0
      Left            =   5880
      Top             =   840
      Width           =   6615
      _ExtentX        =   0
      _ExtentY        =   0
      Begin PhotoDemon.pdButtonStrip btsCompression 
         Height          =   975
         Left            =   240
         TabIndex        =   3
         Top             =   240
         Width           =   6375
         _ExtentX        =   11245
         _ExtentY        =   1720
         Caption         =   "compression"
      End
      Begin PhotoDemon.pdButtonStrip btsCompatibility 
         Height          =   975
         Left            =   240
         TabIndex        =   5
         Top             =   1320
         Width           =   6375
         _ExtentX        =   11245
         _ExtentY        =   1720
         Caption         =   "maximize compatibility"
      End
   End
   Begin PhotoDemon.pdContainer picContainer 
      Height          =   4815
      Index           =   1
      Left            =   5880
      Top             =   840
      Width           =   6615
      _ExtentX        =   0
      _ExtentY        =   0
      Begin PhotoDemon.pdMetadataExport mtdManager 
         Height          =   4215
         Left            =   120
         TabIndex        =   4
         Top             =   120
         Width           =   6375
         _ExtentX        =   11245
         _ExtentY        =   7435
      End
   End
End
Attribute VB_Name = "dialog_ExportPSD"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Adobe Photoshop (PSD) Export Dialog
'Copyright 2019-2020 by Tanner Helland
'Created: 18/February/19
'Last updated: 19/February/19
'Last update: wrap up initial build
'
'This dialog works as a simple relay to the pdPSD class (and its associated child classes).
' Look there for specific encoding details.
'
'I have tried to pare down the UI toggles to only the most essential elements.  Most PSD-compatible
' settings will be automatically generated by PD, where applicable - the caller just needs to
' specify compression (which limits compatibility with some software, so it needs to be accessible),
' and the traditional "max compatibility" setting (which again, limits compatibility with some
' software, but otherwise greatly increases file size).
'
'Unless otherwise noted, all source code in this file is shared under a simplified BSD license.
' Full license details are available in the LICENSE.md file, or at https://photodemon.org/license/
'
'***************************************************************************

Option Explicit

'This form can (and should!) be notified of the image being exported.  The only exception to this rule is invoking
' the dialog from the batch process dialog, as no image is associated with that preview.
Private m_SrcImage As pdImage

'A composite of the current image, 32-bpp, fully composited.  This is only regenerated if the source image changes.
Private m_CompositedImage As pdDIB

'OK or CANCEL result
Private m_UserDialogAnswer As VbMsgBoxResult

'Final format-specific XML packet, with all format-specific settings defined as tag+value pairs
Private m_FormatParamString As String

'Final metadata XML packet, with all metadata settings defined as tag+value pairs
Private m_MetadataParamString As String

'The user's answer is returned via this property
Public Function GetDialogResult() As VbMsgBoxResult
    GetDialogResult = m_UserDialogAnswer
End Function

Public Function GetFormatParams() As String
    GetFormatParams = m_FormatParamString
End Function

Public Function GetMetadataParams() As String
    GetMetadataParams = m_MetadataParamString
End Function

Private Sub btsCategory_Click(ByVal buttonIndex As Long)
    UpdatePanelVisibility
End Sub

Private Sub cmdBar_CancelClick()
    m_UserDialogAnswer = vbCancel
    Me.Visible = False
End Sub

Private Sub cmdBar_OKClick()

    Dim cParams As pdSerialize
    Set cParams = New pdSerialize
    cParams.AddParam "compression", btsCompression.ListIndex
    cParams.AddParam "max-compatibility", (btsCompatibility.ListIndex = 1)
    
    m_FormatParamString = cParams.GetParamString
    
    'The metadata panel manages its own XML string
    m_MetadataParamString = mtdManager.GetMetadataSettings
    
    'Free resources that are no longer required
    Set m_CompositedImage = Nothing
    Set m_SrcImage = Nothing
    
    'Hide but *DO NOT UNLOAD* the form.  The dialog manager needs to retrieve the setting strings before unloading us
    m_UserDialogAnswer = vbOK
    Me.Visible = False

End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()
    mtdManager.Reset
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

'The ShowDialog routine presents the user with this form.
Public Sub ShowDialog(Optional ByRef srcImage As pdImage = Nothing)
    
    'Provide a default answer of "cancel" (in the event that the user clicks the "x" button in the top-right)
    m_UserDialogAnswer = vbCancel
    
    'Make sure that the proper cursor is set
    Screen.MousePointer = 0
    Message "Waiting for user to specify export options... "
    
    'Next, prepare various controls on the metadata panel
    Set m_SrcImage = srcImage
    mtdManager.SetParentImage m_SrcImage, PDIF_PSD
    
    'By default, the basic options panel is always shown.
    btsCategory.AddItem "basic", 0
    btsCategory.AddItem "advanced", 1
    btsCategory.ListIndex = 0
    UpdatePanelVisibility
    
    'Populate any other list elements
    btsCompression.AddItem "none", 0
    btsCompression.AddItem "PackBits", 1
    btsCompression.ListIndex = 1
    
    btsCompatibility.AddItem "no", 0
    btsCompatibility.AddItem "yes", 1
    btsCompatibility.ListIndex = 1
    
    'Prep a preview (if any)
    Set m_SrcImage = srcImage
    If (Not m_SrcImage Is Nothing) Then
        m_SrcImage.GetCompositedImage m_CompositedImage, True
        pdFxPreview.NotifyNonStandardSource m_CompositedImage.GetDIBWidth, m_CompositedImage.GetDIBHeight
    End If
    If (m_SrcImage Is Nothing) Then Interface.ShowDisabledPreviewImage pdFxPreview
    
    UpdatePreview
    
    'Apply translations and visual themes
    ApplyThemeAndTranslations Me
    Strings.SetFormCaptionW Me, g_Language.TranslateMessage("%1 options", "PSD")
    
    'Display the dialog
    ShowPDDialog vbModal, Me, True
    
End Sub

Private Sub UpdatePreview()

    If cmdBar.PreviewsAllowed And (Not m_SrcImage Is Nothing) And (Not m_CompositedImage Is Nothing) Then
        
        'Because the user can change the preview viewport, we can't guarantee that the preview region
        ' hasn't changed since the last preview.  Prep a new preview base image now.
        Dim tmpSafeArray As SafeArray2D
        EffectPrep.PreviewNonStandardImage tmpSafeArray, m_CompositedImage, pdFxPreview, True
        EffectPrep.FinalizeNonstandardPreview pdFxPreview, True
        
    End If

End Sub

Private Sub UpdatePanelVisibility()
    Dim i As Long
    For i = 0 To btsCategory.ListCount - 1
        picContainer(i).Visible = (i = btsCategory.ListIndex)
    Next i
End Sub
