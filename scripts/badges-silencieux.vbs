' =====================================================================
'  badges-silencieux.vbs — enveloppe de trois lignes autour de
'  badges.ps1, appelee par le raccourci du Bureau.
'
'  POURQUOI ELLE EXISTE. Un raccourci qui pointe directement sur
'  powershell.exe fait clignoter une console noire une demi-seconde au
'  demarrage, meme avec -WindowStyle Hidden : l'hote console est cree
'  avant que le script puisse se cacher. wscript.exe, lui, lance le
'  processus avec un style de fenetre 0 des le depart. Rien ne
'  clignote. C'est la seule raison de ce fichier.
'
'  Le troisieme argument False veut dire : ne pas attendre la fin.
'  wscript rend la main tout de suite, badges.ps1 vit sa vie et fermera
'  le serveur quand la fenetre du generateur sera fermee.
' =====================================================================

Dim shell, dossier, commande
Set shell = CreateObject("WScript.Shell")

' Le dossier scripts\, deduit du chemin de ce fichier : le raccourci
' continue de marcher si le projet est deplace ailleurs.
dossier = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

commande = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
         & dossier & "badges.ps1"""

shell.Run commande, 0, False
