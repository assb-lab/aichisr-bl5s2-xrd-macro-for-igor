#pragma TextEncoding = "UTF-8"
#pragma rtGlobals = 3
#pragma IgorVersion = 8.00
#pragma version = 1.10

// ============================================================================
//  AichiSR_BL5S2_XRD.ipf
//  あいちシンクロトロン光センター BL5S2 粉末XRD (Pilatus 自動積算テキスト) 用ビューア
//
//  メニュー "AichiSR" から起動:
//    XRD Profile Viewer         ... フォルダ内の XRD テキストを一覧し、選択したものを色分けして重ね描き
//    XRD 2D Map (temperature)   ... 温度変化などの連続測定を 2D マップ (image) と
//                                   縦オフセット付きプロファイル (stack) で表示。
//                                   温度ログを読み込めば縦軸を実測温度にできる
//
//  対応フォーマット:
//    "#" で始まるヘッダ行 + タブ区切り 3 列 (2θ, 強度, 標準偏差), UTF-8
//    ファイル名  <YYYYMMDDhhmmss>-<試料名>-<連番>.txt   (*_Log.txt は無視)
//    温度ログ    "#" で始まるヘッダ行 + タブ区切り 2 列 (XRD のファイル名, 平均温度)
//
//  データの置き場所:
//    root:AichiXRD:profiles:<名前>       強度 (2θ が等間隔なら X スケーリング付き)
//    root:AichiXRD:profiles:<名前>_tth   2θ
//    root:AichiXRD:profiles:<名前>_esd   標準偏差
//    root:AichiXRD:map:xrdMap            2D マップ (行 = 2θ, 列 = スキャン)
//    root:AichiXRD:map:T_user            温度を手入力するためのウェーブ
//    root:AichiXRD:map:T_file            温度ログから引いた各スキャンの温度
//
//  グラフの体裁 (プロファイル):
//    倍率 2 倍 / フォント 12 pt / 軸ラベル 16 pt / tick 内向き / 縦軸は axis only /
//    単位は "/" 区切り / 右と上にミラー
// ============================================================================

Menu "AichiSR"
	"XRD Profile Viewer", /Q, AXRD_Viewer()
	"XRD 2D Map (temperature series)", /Q, AXRD_Map()
End

StrConstant kAXRD_Pkg    = "root:Packages:AichiXRD"
StrConstant kAXRD_ProfDF = "root:AichiXRD:profiles"
StrConstant kAXRD_MapDF  = "root:AichiXRD:map"
StrConstant kAXRD_VGraph = "AXRD_ViewerGraph"
StrConstant kAXRD_MGraph = "AXRD_MapGraph"
StrConstant kAXRD_SGraph = "AXRD_StackGraph"
StrConstant kAXRD_AllSeries = "All files"
Constant kAXRD_PanelW = 300

// ============================================================================
//  共通: 初期化・状態
// ============================================================================

Function AXRD_Init()
	NewDataFolder/O root:Packages
	NewDataFolder/O $kAXRD_Pkg
	NewDataFolder/O $(kAXRD_Pkg + ":Viewer")
	NewDataFolder/O $(kAXRD_Pkg + ":Map")
	NewDataFolder/O root:AichiXRD
	NewDataFolder/O $kAXRD_ProfDF
	NewDataFolder/O $kAXRD_MapDF

	DFREF df = AXRD_ToolDF("Viewer")
	AXRD_DefListWaves(df)
	AXRD_DefStr(df, "gFolder", "")
	AXRD_DefStr(df, "gFolderDisp", "(no folder)")
	AXRD_DefStr(df, "gFilter", "")
	AXRD_DefStr(df, "gCtab", "Rainbow")
	AXRD_DefVar(df, "gReverse", 1)
	AXRD_DefVar(df, "gOffsetPct", 0)
	AXRD_DefVar(df, "gNormalize", 0)
	AXRD_DefVar(df, "gLog", 0)
	AXRD_DefVar(df, "gLegend", 1)

	DFREF dfM = AXRD_ToolDF("Map")
	AXRD_DefListWaves(dfM)
	AXRD_DefStr(dfM, "gFolder", "")
	AXRD_DefStr(dfM, "gFolderDisp", "(no folder)")
	AXRD_DefStr(dfM, "gSeries", "")
	AXRD_DefStr(dfM, "gSeriesList", kAXRD_AllSeries + ";")
	AXRD_DefStr(dfM, "gStatus", "")
	AXRD_DefVar(dfM, "gYMode", 1)		// 1 scan number, 2 elapsed time, 3 T linear, 4 T table, 5 T file
	AXRD_DefStr(dfM, "gTFileDisp", "(no temperature file)")
	AXRD_DefVar(dfM, "gT0", 300)
	AXRD_DefVar(dfM, "gTStep", 10)
	AXRD_DefVar(dfM, "gTUnit", 1)		// 1 K, 2 degC
	AXRD_DefVar(dfM, "gX1", 0)
	AXRD_DefVar(dfM, "gX2", 0)
	AXRD_DefStr(dfM, "gCtabImg", "Rainbow")
	AXRD_DefVar(dfM, "gRevImg", 1)
	AXRD_DefVar(dfM, "gLogImg", 0)
	AXRD_DefVar(dfM, "gZAuto", 1)
	AXRD_DefVar(dfM, "gZMin", 0)
	AXRD_DefVar(dfM, "gZMax", 1)
	AXRD_DefStr(dfM, "gCtabStk", "Rainbow")
	AXRD_DefVar(dfM, "gRevStk", 1)
	AXRD_DefVar(dfM, "gOffsetPct", 10)
	AXRD_DefVar(dfM, "gEvery", 1)
	AXRD_DefVar(dfM, "gLabels", 0)
End

Function/DF AXRD_ToolDF(tool)
	String tool
	DFREF df = $(kAXRD_Pkg + ":" + tool)
	return df
End

Function/S AXRD_PathName(tool)
	String tool
	return "AXRD_Path_" + tool
End

Function AXRD_DefVar(df, name, val)
	DFREF df
	String name
	Variable val
	NVAR/Z/SDFR=df v = $name
	if (!NVAR_Exists(v))
		DFREF saveDF = GetDataFolderDFR()
		SetDataFolder df
		Variable/G $name = val
		SetDataFolder saveDF
	endif
End

Function AXRD_DefStr(df, name, val)
	DFREF df
	String name, val
	SVAR/Z/SDFR=df sv = $name
	if (!SVAR_Exists(sv))
		DFREF saveDF = GetDataFolderDFR()
		SetDataFolder df
		String/G $name = val
		SetDataFolder saveDF
	endif
End

Function AXRD_DefListWaves(df)
	DFREF df
	Wave/Z/T fw = df:fileW
	if (!WaveExists(fw))
		Make/O/T/N=0 df:fileW, df:listW, df:nameW
		Make/O/B/U/N=0 df:selW
	endif
End

// 画面幅 (ポイント)。ウィンドウ配置に使う。
Function AXRD_ScreenWidth()
	String info = StringByKey("SCREEN1", IgorInfo(0))
	Variable i = strsearch(info, "RECT=", 0)
	Variable sl, st, sr, sb
	if (i < 0)
		return 1440
	endif
	sscanf info[i + 5, inf], "%d,%d,%d,%d", sl, st, sr, sb
	if (V_flag != 4)
		return 1440
	endif
	return sr - sl
End

// 長いパスを末尾 2 階層だけの表示用文字列にする
Function/S AXRD_ShortPath(path)
	String path
	Variable n = ItemsInList(path, ":")
	if (n <= 2)
		return path
	endif
	return "...:" + StringFromList(n - 2, path, ":") + ":" + StringFromList(n - 1, path, ":") + ":"
End

// ============================================================================
//  共通: ファイル一覧・命名
// ============================================================================

// "<14桁タイムスタンプ>-<試料名>-<連番>" を分解する。成功で 1。
Function AXRD_ParseName(base, ts, sample, num)
	String base
	String &ts, &sample, &num
	String a, b, c
	SplitString/E="^([0-9]{14})-(.+)-([0-9]+)$" base, a, b, c
	if (V_flag != 3)
		ts = ""
		sample = ""
		num = ""
		return 0
	endif
	ts = a
	sample = b
	num = c
	return 1
End

Function AXRD_StampToSecs(ts)
	String ts
	Variable yy, mo, dd, hh, mi, ss
	sscanf ts, "%4d%2d%2d%2d%2d%2d", yy, mo, dd, hh, mi, ss
	if (V_flag != 6)
		return NaN
	endif
	return date2secs(yy, mo, dd) + hh * 3600 + mi * 60 + ss
End

// 凡例用の短い名前: "<試料名>-<連番>" (タイムスタンプを外す)
Function/S AXRD_ShortLabel(base)
	String base
	String ts, sample, num
	if (AXRD_ParseName(base, ts, sample, num))
		return sample + "-" + num
	endif
	return base
End

// ファイル名 → ウェーブ名 (タイムスタンプを外した標準名)
Function/S AXRD_WaveNameFromFile(fileName, withStamp)
	String fileName
	Variable withStamp
	String base = ParseFilePath(3, fileName, ":", 0, 0)
	String ts, rest
	SplitString/E="^([0-9]{14})-(.+)$" base, ts, rest
	if (V_flag == 2 && !withStamp)
		base = rest
	endif
	return CleanupName(base, 0)
End

Function AXRD_ChooseFolder(tool)
	String tool
	String pathName = AXRD_PathName(tool)
	NewPath/O/Q/M="Select the folder that contains the XRD text files" $pathName
	if (V_flag != 0)
		return -1		// cancelled
	endif
	AXRD_FolderChanged(tool)
	return 0
End

Function AXRD_FolderChanged(tool)
	String tool
	DFREF df = AXRD_ToolDF(tool)
	SVAR gFolder = df:gFolder
	SVAR gFolderDisp = df:gFolderDisp
	PathInfo $AXRD_PathName(tool)
	if (V_flag)
		gFolder = S_path
		gFolderDisp = AXRD_ShortPath(S_path)
	else
		gFolder = ""
		gFolderDisp = "(no folder)"
	endif
End

// フォルダを読み直してリストを作り直す。選択状態はファイル名で引き継ぐ。
Function AXRD_Rescan(tool)
	String tool
	DFREF df = AXRD_ToolDF(tool)
	Wave/T fileW = df:fileW
	Wave/T listW = df:listW
	Wave/T nameW = df:nameW
	Wave selW = df:selW
	SVAR/Z gFilter = df:gFilter
	SVAR/Z gSeries = df:gSeries
	String pathName = AXRD_PathName(tool)

	Variable i, n = numpnts(fileW)
	String prevSel = ""
	for (i = 0; i < n; i += 1)
		if (selW[i] & 9)
			prevSel = AddListItem(fileW[i], prevSel, ";", inf)
		endif
	endfor

	PathInfo $pathName
	if (!V_flag)
		Redimension/N=0 fileW, listW, nameW, selW
		return 0
	endif

	String filt = ""
	if (SVAR_Exists(gFilter))
		filt = gFilter
		if (strlen(filt) > 0 && strsearch(filt, "*", 0) < 0)
			filt = "*" + filt + "*"
		endif
	endif
	String series = ""
	if (SVAR_Exists(gSeries))
		series = gSeries
	endif

	String all = SortList(IndexedFile($pathName, -1, ".txt"), ";", 16)
	n = ItemsInList(all)
	Redimension/N=(n) fileW, listW, nameW, selW
	Variable k = 0
	String f, base, ts, sample, num, wn
	String used = ""
	for (i = 0; i < n; i += 1)
		f = StringFromList(i, all)
		if (StringMatch(f, "*_Log.txt"))
			continue
		endif
		if (strlen(filt) > 0 && !StringMatch(f, filt))
			continue
		endif
		base = ParseFilePath(3, f, ":", 0, 0)
		if (strlen(series) > 0)
			if (!AXRD_ParseName(base, ts, sample, num))
				continue
			endif
			if (CmpStr(sample, series) != 0)
				continue
			endif
		endif
		fileW[k] = f
		listW[k] = base
		wn = AXRD_WaveNameFromFile(f, 0)
		if (WhichListItem(wn, used) >= 0)
			wn = AXRD_WaveNameFromFile(f, 1)		// 同名があればタイムスタンプ付きに
		endif
		used = AddListItem(wn, used, ";", inf)
		nameW[k] = wn
		selW[k] = (WhichListItem(f, prevSel) >= 0)
		k += 1
	endfor
	Redimension/N=(k) fileW, listW, nameW, selW
	return k
End

// ============================================================================
//  共通: 読み込み
// ============================================================================

// 1 ファイルを読み込み、強度ウェーブの参照を返す (失敗時は null)。
// 同じファイル (パスと更新日時が同じ) が読み込み済みならそれを再利用する。
Function/WAVE AXRD_LoadFile(pathName, fileName, wName)
	String pathName, fileName, wName

	DFREF profDF = $kAXRD_ProfDF
	PathInfo $pathName
	if (!V_flag)
		return $""
	endif
	String sig = S_path + fileName
	GetFileFolderInfo/Q/Z/P=$pathName fileName
	if (V_flag != 0 || !V_isFile)
		return $""
	endif
	String modStr
	sprintf modStr, "%.0f", V_modificationDate
	sig += "|" + modStr

	Wave/Z cachedI = profDF:$wName
	Wave/Z cachedX = profDF:$(wName + "_tth")
	if (WaveExists(cachedI) && WaveExists(cachedX))
		if (CmpStr(StringByKey("SRC", note(cachedI), "=", "\r"), sig) == 0)
			return cachedI
		endif
	endif

	DFREF saveDF = GetDataFolderDFR()
	DFREF tmpDF = NewFreeDataFolder()
	SetDataFolder tmpDF
	LoadWave/G/D/Q/N=axrdTmp/ENCG=1/P=$pathName fileName
	Variable err = GetRTError(1)
	SetDataFolder saveDF
	Wave/Z c0 = tmpDF:axrdTmp0
	Wave/Z c1 = tmpDF:axrdTmp1
	Wave/Z c2 = tmpDF:axrdTmp2
	if (err != 0 || !WaveExists(c0) || !WaveExists(c1))
		Print "AichiXRD: could not load " + fileName
		return $""
	endif

	Duplicate/O c1, profDF:$wName
	Duplicate/O c0, profDF:$(wName + "_tth")
	if (WaveExists(c2))
		Duplicate/O c2, profDF:$(wName + "_esd")
	endif
	Wave wInt = profDF:$wName
	Wave wTth = profDF:$(wName + "_tth")

	// 2θ が等間隔なら強度ウェーブに X スケーリングを付けておく
	Variable np = numpnts(wTth)
	Variable uniform = 0
	if (np > 1)
		Variable x0 = wTth[0]
		Variable dx = (wTth[np - 1] - x0) / (np - 1)
		Make/FREE/D/N=(np) dev
		dev = abs(wTth[p] - (x0 + p * dx))
		if (dx > 0 && WaveMax(dev) < 0.01 * dx)
			SetScale/P x, x0, dx, "", wInt
			uniform = 1
		endif
	endif
	Note/K wInt, "SRC=" + sig + "\rFILE=" + fileName + "\rUNIFORM=" + num2istr(uniform)
	return wInt
End

// ============================================================================
//  共通: 色・体裁
// ============================================================================

// カラーテーブルを N x 3 のフリーウェーブで返す
Function/WAVE AXRD_ColorWave(ctab)
	String ctab
	if (WhichListItem(ctab, CTabList()) < 0)
		ctab = "Rainbow"
	endif
	DFREF saveDF = GetDataFolderDFR()
	DFREF tmpDF = NewFreeDataFolder()
	SetDataFolder tmpDF
	ColorTab2Wave $ctab
	Wave M_colors = tmpDF:M_colors
	Duplicate/FREE M_colors, cw
	SetDataFolder saveDF
	return cw
End

// frac (0-1) に対応するカラーテーブルの行番号
Function AXRD_ColorRow(cw, frac, rev)
	Wave cw
	Variable frac, rev
	Variable nc = DimSize(cw, 0)
	frac = limit(frac, 0, 1)
	if (rev)
		frac = 1 - frac
	endif
	return round(frac * (nc - 1))
End

// X 線回折図形の体裁: フォント 12 / 軸ラベル 16 / tick 内向き / 縦は axis only / ミラー
Function AXRD_ApplyProfileStyle(g)
	String g
	if (ItemsInList(TraceNameList(g, ";", 1)) == 0)
		return 0
	endif
	ModifyGraph/W=$g gfSize=12, tick=2, mirror=1
	ModifyGraph/W=$g noLabel(left)=1
	String xl = "\\Z16" + "2\\f02θ\\f00 / deg."
	String yl = "\\Z16" + "Intensity / a.u."
	Label/W=$g bottom xl
	Label/W=$g left yl
	return 1
End

Function AXRD_KillAnnotation(g, name)
	String g, name
	if (WhichListItem(name, AnnotationList(g)) >= 0)
		TextBox/W=$g/K/N=$name
	endif
End

Function AXRD_CtabPopMode(ctab)
	String ctab
	Variable i = WhichListItem(ctab, CTabList())
	return (i < 0) ? 1 : i + 1
End

// ============================================================================
//  Profile Viewer
// ============================================================================

Function AXRD_Viewer()
	AXRD_Init()
	String g = kAXRD_VGraph
	DoWindow/F $g
	if (V_flag)
		return 0
	endif

	DFREF df = AXRD_ToolDF("Viewer")
	SVAR gFolderDisp = df:gFolderDisp
	SVAR gFilter = df:gFilter
	SVAR gCtab = df:gCtab
	NVAR gReverse = df:gReverse
	NVAR gOffsetPct = df:gOffsetPct
	NVAR gNormalize = df:gNormalize
	NVAR gLog = df:gLog
	NVAR gLegend = df:gLegend
	Wave/T listW = df:listW
	Wave selW = df:selW

	Variable winL = kAXRD_PanelW + 40
	Display/K=1/N=$g/W=(winL, 70, winL + 400, 70 + 280) as "BL5S2 XRD - Profile Viewer"
	ModifyGraph/W=$g expand=2

	// 左側の外付けパネルでは /W=(幅, 最小の高さ, ホストとの隙間, 高さ[0=ホストに合わせる])
	NewPanel/HOST=$g/EXT=1/N=ctrl/W=(kAXRD_PanelW, 510, 0, 0) as "XRD files"
	String pn = g + "#ctrl"

	Button btnOpen, win=$pn, pos={8, 6}, size={110, 22}, title="Open Folder...", proc=AXRD_VButtonProc
	Button btnRescan, win=$pn, pos={124, 6}, size={64, 22}, title="Rescan", proc=AXRD_VButtonProc
	Button btnMap, win=$pn, pos={212, 6}, size={80, 22}, title="2D Map...", proc=AXRD_VButtonProc
	TitleBox tbPath, win=$pn, pos={8, 33}, size={284, 16}, fixedSize=1, frame=0, variable=gFolderDisp
	SetVariable svFilter, win=$pn, pos={8, 54}, size={284, 18}, bodyWidth=240, title="Filter", value=gFilter, proc=AXRD_VSetVarProc
	SetVariable svFilter, win=$pn, help={"Show only file names that contain this text. Wildcard * is allowed."}
	ListBox lbFiles, win=$pn, pos={8, 78}, size={284, 270}, listWave=listW, selWave=selW, mode=9, proc=AXRD_VListProc
	Button btnAll, win=$pn, pos={8, 354}, size={60, 20}, title="All", proc=AXRD_VButtonProc
	Button btnNone, win=$pn, pos={74, 354}, size={60, 20}, title="None", proc=AXRD_VButtonProc
	Button btnAuto, win=$pn, pos={212, 354}, size={80, 20}, title="Autoscale", proc=AXRD_VButtonProc

	GroupBox gbDisp, win=$pn, pos={4, 382}, size={292, 118}, title="Display"
	PopupMenu popCtab, win=$pn, pos={12, 402}, size={200, 20}, bodyWidth=150, title="Colors", proc=AXRD_VPopupProc
	PopupMenu popCtab, win=$pn, value="*COLORTABLEPOP*", mode=AXRD_CtabPopMode(gCtab)
	CheckBox cbReverse, win=$pn, pos={220, 405}, size={70, 16}, title="Reverse", variable=gReverse, proc=AXRD_VCheckProc
	SetVariable svOffset, win=$pn, pos={12, 430}, size={150, 18}, bodyWidth=70, title="Offset / %", value=gOffsetPct, proc=AXRD_VSetVarProc
	SetVariable svOffset, win=$pn, limits={-1000, 1000, 5}, help={"Vertical offset between traces, in % of the largest intensity."}
	CheckBox cbNorm, win=$pn, pos={180, 432}, size={110, 16}, title="Normalize", variable=gNormalize, proc=AXRD_VCheckProc
	CheckBox cbLog, win=$pn, pos={12, 458}, size={110, 16}, title="Log intensity", variable=gLog, proc=AXRD_VCheckProc
	CheckBox cbLegend, win=$pn, pos={180, 458}, size={110, 16}, title="Legend", variable=gLegend, proc=AXRD_VCheckProc

	SetActiveSubwindow $g
	AXRD_ViewerUpdate()
End

// 選択状態にグラフを合わせる。追加→削除の順にして軸 (ズーム状態) を保つ。
Function AXRD_ViewerUpdate()
	String g = kAXRD_VGraph
	DoWindow $g
	if (!V_flag)
		return 0
	endif
	DFREF df = AXRD_ToolDF("Viewer")
	DFREF profDF = $kAXRD_ProfDF
	Wave/T fileW = df:fileW
	Wave/T listW = df:listW
	Wave/T nameW = df:nameW
	Wave selW = df:selW
	SVAR gCtab = df:gCtab
	NVAR gReverse = df:gReverse
	NVAR gOffsetPct = df:gOffsetPct
	NVAR gNormalize = df:gNormalize
	NVAR gLog = df:gLog
	NVAR gLegend = df:gLegend
	String pathName = AXRD_PathName("Viewer")

	Variable i, n = numpnts(selW)
	String want = "", labels = "", tn
	for (i = 0; i < n; i += 1)
		if (selW[i] & 9)
			Wave/Z wNew = AXRD_LoadFile(pathName, fileW[i], nameW[i])
			if (WaveExists(wNew))
				want = AddListItem(nameW[i], want, ";", inf)
				labels = AddListItem(AXRD_ShortLabel(listW[i]), labels, ";", inf)
			endif
		endif
	endfor

	String have = TraceNameList(g, ";", 1)
	Variable nHave = ItemsInList(have)
	Variable nWant = ItemsInList(want)
	for (i = 0; i < nWant; i += 1)
		tn = StringFromList(i, want)
		if (WhichListItem(tn, have) < 0)
			Wave wA = profDF:$tn
			Wave wAx = profDF:$(tn + "_tth")
			AppendToGraph/W=$g wA vs wAx
		endif
	endfor
	for (i = nHave - 1; i >= 0; i -= 1)
		tn = StringFromList(i, have)
		if (WhichListItem(tn, want) < 0)
			RemoveFromGraph/W=$g $tn
		endif
	endfor

	if (nWant == 0)
		AXRD_KillAnnotation(g, "axrdLeg")
		return 0
	endif
	if (nHave == 0)
		AXRD_ApplyProfileStyle(g)		// 空のグラフに最初のトレースが入ったときだけ体裁を整える
	endif

	Make/FREE/D/N=(nWant) maxW
	Variable m
	for (i = 0; i < nWant; i += 1)
		Wave wB = profDF:$StringFromList(i, want)
		m = WaveMax(wB)
		maxW[i] = (numtype(m) == 0 && m > 0) ? m : 1
	endfor
	Variable gmax = gNormalize ? 1 : WaveMax(maxW)

	Wave cw = AXRD_ColorWave(gCtab)
	Variable row, mul, off
	String leg = ""
	for (i = 0; i < nWant; i += 1)
		tn = StringFromList(i, want)
		mul = gNormalize ? 1 / maxW[i] : 0
		off = i * gOffsetPct / 100 * gmax
		row = AXRD_ColorRow(cw, (nWant > 1) ? i / (nWant - 1) : 0, gReverse)
		ModifyGraph/W=$g muloffset($tn)={0, mul}, offset($tn)={0, off}
		ModifyGraph/W=$g rgb($tn)=(cw[row][0], cw[row][1], cw[row][2])
		// 上に積まれたトレースが凡例でも上に来るよう、逆順に並べる
		leg = "\\s(" + tn + ") " + StringFromList(i, labels) + SelectString(strlen(leg) > 0, "", "\r") + leg
	endfor
	ModifyGraph/W=$g log(left)=(gLog != 0)

	if (gLegend)
		if (WhichListItem("axrdLeg", AnnotationList(g)) >= 0)
			Legend/W=$g/C/N=axrdLeg/J leg
		else
			Legend/W=$g/C/N=axrdLeg/J/F=0/B=1/A=RT leg
		endif
	else
		AXRD_KillAnnotation(g, "axrdLeg")
	endif
	return nWant
End

Function AXRD_VButtonProc(ba) : ButtonControl
	STRUCT WMButtonAction &ba
	if (ba.eventCode != 2)
		return 0
	endif
	DFREF df = AXRD_ToolDF("Viewer")
	Wave selW = df:selW
	strswitch (ba.ctrlName)
		case "btnOpen":
			if (AXRD_ChooseFolder("Viewer") == 0)
				AXRD_Rescan("Viewer")
				AXRD_ViewerUpdate()
			endif
			break
		case "btnRescan":
			AXRD_Rescan("Viewer")
			AXRD_ViewerUpdate()
			break
		case "btnAll":
			selW = 1
			AXRD_ViewerUpdate()
			break
		case "btnNone":
			selW = 0
			AXRD_ViewerUpdate()
			break
		case "btnAuto":
			if (ItemsInList(TraceNameList(kAXRD_VGraph, ";", 1)) > 0)
				SetAxis/A/W=$kAXRD_VGraph
			endif
			break
		case "btnMap":
			AXRD_OpenMapFromViewer()
			break
	endswitch
	return 0
End

Function AXRD_VListProc(lba) : ListBoxControl
	STRUCT WMListboxAction &lba
	switch (lba.eventCode)
		case 2:		// mouse up
		case 4:		// cell selection
		case 5:		// cell selection + shift
			AXRD_ViewerUpdate()
			break
	endswitch
	return 0
End

Function AXRD_VSetVarProc(sva) : SetVariableControl
	STRUCT WMSetVariableAction &sva
	switch (sva.eventCode)
		case 1:		// mouse up
		case 2:		// Enter
			if (CmpStr(sva.ctrlName, "svFilter") == 0)
				AXRD_Rescan("Viewer")
			endif
			AXRD_ViewerUpdate()
			break
	endswitch
	return 0
End

Function AXRD_VCheckProc(cba) : CheckBoxControl
	STRUCT WMCheckboxAction &cba
	if (cba.eventCode == 2)
		AXRD_ViewerUpdate()
	endif
	return 0
End

Function AXRD_VPopupProc(pa) : PopupMenuControl
	STRUCT WMPopupAction &pa
	if (pa.eventCode == 2)
		DFREF df = AXRD_ToolDF("Viewer")
		SVAR gCtab = df:gCtab
		gCtab = pa.popStr
		AXRD_ViewerUpdate()
	endif
	return 0
End

// Viewer で開いているフォルダをそのまま 2D Map に引き継ぐ
Function AXRD_OpenMapFromViewer()
	DFREF dfV = AXRD_ToolDF("Viewer")
	DFREF dfM = AXRD_ToolDF("Map")
	SVAR vFolder = dfV:gFolder
	SVAR mFolder = dfM:gFolder
	AXRD_Map()
	if (strlen(mFolder) == 0 && strlen(vFolder) > 0)
		NewPath/O/Q $AXRD_PathName("Map"), vFolder
		AXRD_MapFolderOpened()
	endif
End

// ============================================================================
//  2D Map (温度変化などの連続測定)
// ============================================================================

Function AXRD_Map()
	AXRD_Init()
	String g = kAXRD_MGraph
	DoWindow/F $g
	if (V_flag)
		return 0
	endif

	DFREF df = AXRD_ToolDF("Map")
	SVAR gFolderDisp = df:gFolderDisp
	SVAR gStatus = df:gStatus
	SVAR gTFileDisp = df:gTFileDisp
	SVAR gCtabImg = df:gCtabImg
	SVAR gCtabStk = df:gCtabStk
	NVAR gYMode = df:gYMode
	NVAR gT0 = df:gT0
	NVAR gTStep = df:gTStep
	NVAR gTUnit = df:gTUnit
	NVAR gX1 = df:gX1
	NVAR gX2 = df:gX2
	NVAR gRevImg = df:gRevImg
	NVAR gLogImg = df:gLogImg
	NVAR gZAuto = df:gZAuto
	NVAR gZMin = df:gZMin
	NVAR gZMax = df:gZMax
	NVAR gRevStk = df:gRevStk
	NVAR gOffsetPct = df:gOffsetPct
	NVAR gEvery = df:gEvery
	NVAR gLabels = df:gLabels
	Wave/T listW = df:listW
	Wave selW = df:selW

	Variable winL = kAXRD_PanelW + 40
	Display/K=1/N=$g/W=(winL, 70, winL + 360, 70 + 320) as "BL5S2 XRD - 2D Map"
	ModifyGraph/W=$g expand=2

	NewPanel/HOST=$g/EXT=1/N=ctrl/W=(kAXRD_PanelW, 664, 0, 0) as "2D map controls"
	String pn = g + "#ctrl"

	Button btnOpen, win=$pn, pos={8, 6}, size={110, 22}, title="Open Folder...", proc=AXRD_MButtonProc
	Button btnRescan, win=$pn, pos={124, 6}, size={64, 22}, title="Rescan", proc=AXRD_MButtonProc
	TitleBox tbPath, win=$pn, pos={8, 33}, size={284, 16}, fixedSize=1, frame=0, variable=gFolderDisp
	PopupMenu popSeries, win=$pn, pos={8, 52}, size={284, 20}, bodyWidth=236, title="Series", proc=AXRD_MPopupProc
	PopupMenu popSeries, win=$pn, value=#"AXRD_SeriesPopList()", mode=1
	ListBox lbFiles, win=$pn, pos={8, 78}, size={284, 170}, listWave=listW, selWave=selW, mode=9
	Button btnAll, win=$pn, pos={8, 254}, size={50, 22}, title="All", proc=AXRD_MButtonProc
	Button btnNone, win=$pn, pos={62, 254}, size={50, 22}, title="None", proc=AXRD_MButtonProc
	Button btnBuild, win=$pn, pos={172, 254}, size={120, 22}, title="Build Map", fStyle=1, proc=AXRD_MButtonProc

	GroupBox gbY, win=$pn, pos={4, 284}, size={292, 106}, title="Y axis"
	PopupMenu popYMode, win=$pn, pos={12, 302}, size={200, 20}, bodyWidth=200, proc=AXRD_MPopupProc
	PopupMenu popYMode, win=$pn, value="Scan number;Elapsed time / min;Temperature (start + step);Temperature (table);Temperature (file)", mode=gYMode
	PopupMenu popUnit, win=$pn, pos={222, 302}, size={66, 20}, bodyWidth=66, proc=AXRD_MPopupProc
	PopupMenu popUnit, win=$pn, value="K;°C", mode=gTUnit
	SetVariable svT0, win=$pn, pos={12, 332}, size={92, 18}, bodyWidth=56, title="Start", value=gT0, proc=AXRD_MSetVarProc
	SetVariable svTStep, win=$pn, pos={110, 332}, size={86, 18}, bodyWidth=56, title="Step", value=gTStep, proc=AXRD_MSetVarProc
	Button btnEditT, win=$pn, pos={206, 330}, size={84, 22}, title="Edit table...", proc=AXRD_MButtonProc
	Button btnLoadT, win=$pn, pos={12, 358}, size={100, 22}, title="Load T file...", proc=AXRD_MButtonProc
	Button btnLoadT, win=$pn, help={"Load a temperature log: one line per scan, XRD file name <tab> mean temperature."}
	TitleBox tbTFile, win=$pn, pos={120, 361}, size={170, 16}, fixedSize=1, frame=0, variable=gTFileDisp

	SetVariable svX1, win=$pn, pos={8, 400}, size={118, 18}, bodyWidth=60, title="2θ from", value=gX1, proc=AXRD_MSetVarProc
	SetVariable svX2, win=$pn, pos={132, 400}, size={84, 18}, bodyWidth=60, title="to", value=gX2, proc=AXRD_MSetVarProc
	Button btnFullX, win=$pn, pos={226, 398}, size={66, 22}, title="Full", proc=AXRD_MButtonProc

	GroupBox gbImg, win=$pn, pos={4, 428}, size={292, 96}, title="Image"
	PopupMenu popCtabImg, win=$pn, pos={12, 446}, size={200, 20}, bodyWidth=150, title="Colors", proc=AXRD_MPopupProc
	PopupMenu popCtabImg, win=$pn, value="*COLORTABLEPOP*", mode=AXRD_CtabPopMode(gCtabImg)
	CheckBox cbRevImg, win=$pn, pos={220, 449}, size={70, 16}, title="Reverse", variable=gRevImg, proc=AXRD_MCheckProc
	CheckBox cbLogImg, win=$pn, pos={12, 474}, size={100, 16}, title="Log colors", variable=gLogImg, proc=AXRD_MCheckProc
	CheckBox cbZAuto, win=$pn, pos={150, 474}, size={100, 16}, title="Auto Z range", variable=gZAuto, proc=AXRD_MCheckProc
	SetVariable svZMin, win=$pn, pos={12, 498}, size={132, 18}, bodyWidth=90, title="Z min", value=gZMin, proc=AXRD_MSetVarProc
	SetVariable svZMax, win=$pn, pos={152, 498}, size={136, 18}, bodyWidth=90, title="Z max", value=gZMax, proc=AXRD_MSetVarProc

	GroupBox gbStk, win=$pn, pos={4, 532}, size={292, 96}, title="Stacked profiles"
	PopupMenu popCtabStk, win=$pn, pos={12, 550}, size={200, 20}, bodyWidth=150, title="Colors", proc=AXRD_MPopupProc
	PopupMenu popCtabStk, win=$pn, value="*COLORTABLEPOP*", mode=AXRD_CtabPopMode(gCtabStk)
	CheckBox cbRevStk, win=$pn, pos={220, 553}, size={70, 16}, title="Reverse", variable=gRevStk, proc=AXRD_MCheckProc
	SetVariable svOffset, win=$pn, pos={12, 578}, size={146, 18}, bodyWidth=66, title="Offset / %", value=gOffsetPct, proc=AXRD_MSetVarProc
	SetVariable svOffset, win=$pn, limits={-1000, 1000, 1}, help={"Vertical offset between neighbouring profiles, in % of the largest intensity."}
	SetVariable svEvery, win=$pn, pos={170, 578}, size={118, 18}, bodyWidth=50, title="Every N", value=gEvery, proc=AXRD_MSetVarProc
	SetVariable svEvery, win=$pn, limits={1, 1000, 1}
	CheckBox cbLabels, win=$pn, pos={12, 604}, size={120, 16}, title="Label profiles", variable=gLabels, proc=AXRD_MCheckProc
	Button btnStack, win=$pn, pos={172, 601}, size={116, 22}, title="Show profiles", proc=AXRD_MButtonProc

	TitleBox tbStatus, win=$pn, pos={8, 638}, size={284, 16}, fixedSize=1, frame=0, variable=gStatus

	SetActiveSubwindow $g
	AXRD_MapSyncSeriesPopup()
	AXRD_MapRefresh(1, 0)
End

Function/S AXRD_SeriesPopList()
	DFREF df = AXRD_ToolDF("Map")
	SVAR/Z gSeriesList = df:gSeriesList
	if (!SVAR_Exists(gSeriesList))
		return kAXRD_AllSeries + ";"
	endif
	return gSeriesList
End

// フォルダ内のファイル名から試料名 (シリーズ) を拾い、ポップアップ用リストを作る。
// 現在のシリーズがフォルダに無ければ、ファイル数が最多のシリーズを選ぶ。
Function AXRD_MapScanSeries()
	DFREF df = AXRD_ToolDF("Map")
	SVAR gSeriesList = df:gSeriesList
	SVAR gSeries = df:gSeries
	String pathName = AXRD_PathName("Map")

	gSeriesList = kAXRD_AllSeries + ";"
	PathInfo $pathName
	if (!V_flag)
		gSeries = ""
		return 0
	endif
	String all = SortList(IndexedFile($pathName, -1, ".txt"), ";", 16)
	Variable i, n = ItemsInList(all), idx
	String names = "", f, ts, sample, num
	Make/FREE/N=0 counts
	for (i = 0; i < n; i += 1)
		f = StringFromList(i, all)
		if (StringMatch(f, "*_Log.txt"))
			continue
		endif
		if (!AXRD_ParseName(ParseFilePath(3, f, ":", 0, 0), ts, sample, num))
			continue
		endif
		idx = WhichListItem(sample, names)
		if (idx < 0)
			names = AddListItem(sample, names, ";", inf)
			idx = numpnts(counts)
			InsertPoints idx, 1, counts
			counts[idx] = 0
		endif
		counts[idx] += 1
	endfor

	Variable ns = ItemsInList(names), best = -1
	for (i = 0; i < ns; i += 1)
		gSeriesList += StringFromList(i, names) + " (" + num2istr(counts[i]) + ");"
		if (best < 0 || counts[i] > counts[best])
			best = i
		endif
	endfor
	if (strlen(gSeries) > 0 && WhichListItem(gSeries, names) < 0)
		gSeries = ""
	endif
	if (strlen(gSeries) == 0 && best >= 0)
		gSeries = StringFromList(best, names)
	endif
	return ns
End

Function AXRD_MapSyncSeriesPopup()
	DoWindow $kAXRD_MGraph
	if (!V_flag)
		return 0
	endif
	DFREF df = AXRD_ToolDF("Map")
	SVAR gSeriesList = df:gSeriesList
	SVAR gSeries = df:gSeries
	String pn = kAXRD_MGraph + "#ctrl"
	Variable i, n = ItemsInList(gSeriesList), sel = 1
	String item
	for (i = 1; i < n; i += 1)
		item = StringFromList(i, gSeriesList)
		if (CmpStr(AXRD_SeriesFromPopStr(item), gSeries) == 0)
			sel = i + 1
			break
		endif
	endfor
	PopupMenu popSeries, win=$pn, mode=sel
	ControlUpdate/W=$pn popSeries
End

// "SampleA (40)" → "SampleA"。"All files" は ""。
Function/S AXRD_SeriesFromPopStr(popStr)
	String popStr
	if (CmpStr(popStr, kAXRD_AllSeries) == 0)
		return ""
	endif
	Variable i = strsearch(popStr, " (", inf, 1)
	if (i < 0)
		return popStr
	endif
	return popStr[0, i - 1]
End

Function AXRD_MapFolderOpened()
	DFREF df = AXRD_ToolDF("Map")
	Wave selW = df:selW
	SVAR gSeries = df:gSeries
	SVAR gStatus = df:gStatus
	AXRD_FolderChanged("Map")
	AXRD_MapScanSeries()
	AXRD_MapSyncSeriesPopup()
	selW = 0
	Variable n = AXRD_Rescan("Map")
	if (strlen(gSeries) > 0)
		selW = 1
	endif
	sprintf gStatus, "%d files. Select scans, then Build Map.", n
End

Function AXRD_MapClearGraphs()
	String g = kAXRD_MGraph
	Variable i
	String tl, tn
	DoWindow $g
	if (V_flag)
		AXRD_KillAnnotation(g, "axrdCS")
		if (WhichListItem("xrdMap", ImageNameList(g, ";")) >= 0)
			RemoveImage/W=$g xrdMap
		endif
	endif
	g = kAXRD_SGraph
	DoWindow $g
	if (V_flag)
		tl = TraceNameList(g, ";", 1)
		for (i = ItemsInList(tl) - 1; i >= 0; i -= 1)
			tn = StringFromList(i, tl)
			RemoveFromGraph/W=$g $tn
		endfor
	endif
End

// 選択されたスキャンを読み込み、共通の 2θ グリッドに載せて 2D マップを作る
Function AXRD_MapBuild()
	DFREF df = AXRD_ToolDF("Map")
	DFREF profDF = $kAXRD_ProfDF
	DFREF mapDF = $kAXRD_MapDF
	Wave/T fileW = df:fileW
	Wave/T listW = df:listW
	Wave/T nameW = df:nameW
	Wave selW = df:selW
	SVAR gStatus = df:gStatus
	String pathName = AXRD_PathName("Map")
	String pn = kAXRD_MGraph + "#ctrl"

	Variable i, n = numpnts(selW), ns = 0
	for (i = 0; i < n; i += 1)
		ns += (selW[i] & 9) != 0
	endfor
	if (ns < 2)
		gStatus = "Select two or more scans first."
		return -1
	endif

	Make/FREE/WAVE/N=(ns) refI, refX
	Make/FREE/T/N=(ns) labs
	Make/FREE/D/N=(ns) nums, secs
	Variable j = 0, ok
	String ts, sample, num
	for (i = 0; i < n; i += 1)
		if (!(selW[i] & 9))
			continue
		endif
		sprintf gStatus, "Loading %d / %d ...", j + 1, ns
		ControlUpdate/W=$pn tbStatus
		Wave/Z wi1 = AXRD_LoadFile(pathName, fileW[i], nameW[i])
		if (!WaveExists(wi1))
			continue
		endif
		Wave wx1 = profDF:$(nameW[i] + "_tth")
		if (numpnts(wx1) < 2)
			continue
		endif
		refI[j] = wi1
		refX[j] = wx1
		labs[j] = listW[i]
		ok = AXRD_ParseName(listW[i], ts, sample, num)
		nums[j] = ok ? str2num(num) : NaN
		secs[j] = ok ? AXRD_StampToSecs(ts) : NaN
		j += 1
	endfor
	ns = j
	if (ns < 2)
		gStatus = "Could not load enough scans."
		return -1
	endif
	Redimension/N=(ns) refI, refX, labs, nums, secs

	// 共通グリッド: 全スキャンの 2θ 範囲の和集合、刻みは 1 本目に合わせる
	Variable xmin = inf, xmax = -inf, dx = NaN, np
	for (j = 0; j < ns; j += 1)
		Wave wx2 = refX[j]
		np = numpnts(wx2)
		xmin = min(xmin, wx2[0])
		xmax = max(xmax, wx2[np - 1])
		if (numtype(dx) != 0)
			dx = (wx2[np - 1] - wx2[0]) / (np - 1)
		endif
	endfor
	if (!(dx > 0))
		gStatus = "Bad 2theta axis in the first scan."
		return -1
	endif
	Variable nx = round((xmax - xmin) / dx) + 1

	AXRD_MapClearGraphs()

	// 同じスキャンの並びなら手入力した温度を残す
	Variable keepT = 0
	Wave/Z/T oldLab = mapDF:scanLabel
	Wave/Z oldT = mapDF:T_user
	if (WaveExists(oldLab) && WaveExists(oldT))
		if (numpnts(oldLab) == ns && numpnts(oldT) == ns)
			keepT = EqualWaves(oldLab, labs, 1)
		endif
	endif

	Make/O/D/N=(nx, ns) mapDF:xrdMap
	Wave M = mapDF:xrdMap
	SetScale/P x, xmin, dx, "", M
	SetScale/P y, 0, 1, "", M
	M = NaN
	Variable xs, xe, tol = 0.01 * dx
	for (j = 0; j < ns; j += 1)
		Wave wi3 = refI[j]
		Wave wx3 = refX[j]
		xs = wx3[0] - tol
		xe = wx3[numpnts(wx3) - 1] + tol
		M[][j] = (x >= xs && x <= xe) ? interp(x, wx3, wi3) : NaN
	endfor

	Duplicate/O labs, mapDF:scanLabel
	WaveStats/Q/M=1 nums
	if (V_numNaNs > 0)
		nums = p + 1
	endif
	Duplicate/O nums, mapDF:scanNum
	Variable t0 = secs[0]
	secs = (secs[p] - t0) / 60
	Duplicate/O secs, mapDF:scanTime
	if (!keepT)
		Make/O/D/N=(ns) mapDF:T_user = NaN
	endif
	AXRD_MapFillTFile()

	sprintf gStatus, "Map built: %d scans x %d points.", ns, nx
	AXRD_MapRefresh(1, 1)
	return 0
End

// Y 軸の値 (scanY) と image 用の境界 (scanYEdge) を作る。
// Y が単調なら 1 を返す。単調でなければ 0 を返し、image をスキャン順に描くための
// 目盛りウェーブ (yTickPos, yTickLab) を用意する。
Function AXRD_MapComputeY(yLab, imgYLab, tagFmt)
	String &yLab, &imgYLab, &tagFmt
	DFREF df = AXRD_ToolDF("Map")
	DFREF mapDF = $kAXRD_MapDF
	NVAR gYMode = df:gYMode
	NVAR gT0 = df:gT0
	NVAR gTStep = df:gTStep
	NVAR gTUnit = df:gTUnit
	SVAR gStatus = df:gStatus
	Wave M = mapDF:xrdMap
	Wave scanNum = mapDF:scanNum
	Wave scanTime = mapDF:scanTime
	Wave T_user = mapDF:T_user
	Variable ns = DimSize(M, 1)

	Make/O/D/N=(ns) mapDF:scanY
	Make/O/D/N=(ns + 1) mapDF:scanYEdge
	Wave sy = mapDF:scanY
	Wave se = mapDF:scanYEdge
	String unit = SelectString(gTUnit == 2, "K", "°C")
	if (StringMatch(gStatus, "Y *"))
		gStatus = ""		// 前回の Y 軸に関する注意書きを消す
	endif

	switch (gYMode)
		case 2:
			sy = scanTime[p]
			yLab = "Elapsed time / min"
			tagFmt = "%.1f min"
			break
		case 3:
			sy = gT0 + p * gTStep
			yLab = "Temperature / " + unit
			tagFmt = "%g " + unit
			break
		case 4:
			sy = T_user[p]
			yLab = "Temperature / " + unit
			tagFmt = "%g " + unit
			break
		case 5:
			AXRD_MapFillTFile()
			Wave T_file = mapDF:T_file
			sy = T_file[p]
			yLab = "Temperature / " + unit
			tagFmt = "%g " + unit
			break
		default:
			sy = scanNum[p]
			yLab = "Scan number"
			tagFmt = "#%g"
			break
	endswitch

	WaveStats/Q/M=1 sy
	if (V_numNaNs + V_numINFs > 0)
		gStatus = "Y values are missing; scan index is used."
		if (gYMode == 5)
			gStatus = "Y is missing in the T file; scan index is used."
		endif
		sy = p + 1
		yLab = "Scan index"
		tagFmt = "#%g"
	endif

	// image の Y は単調でないと描けない (昇温→保持→降温など)。その場合はスキャン順に並べ、
	// 目盛りにだけ Y の値 (温度など) を書く
	Variable mono = 1, j, d, s0 = 0
	for (j = 1; j < ns; j += 1)
		d = sy[j] - sy[j - 1]
		if (d == 0)
			mono = 0
		elseif (s0 == 0)
			s0 = sign(d)
		elseif (sign(d) != s0)
			mono = 0
		endif
	endfor
	Make/FREE/D/N=(ns) src
	if (mono)
		src = sy[p]
		imgYLab = yLab
	else
		src = p + 1
		imgYLab = yLab
		AXRD_MapMakeYTicks(sy)
		gStatus = "Y is not monotonic; the image is in scan order."
	endif
	if (ns == 1)
		se[0] = src[0] - 0.5
		se[1] = src[0] + 0.5
	else
		se[1, ns - 1] = (src[p - 1] + src[p]) / 2
		se[0] = src[0] - (src[1] - src[0]) / 2
		se[ns] = src[ns - 1] + (src[ns - 1] - src[ns - 2]) / 2
	endif
	return mono
End

// 目盛りの刻みに使う、きりのよい数 (1, 2, 5 × 10^n) のうち raw 以上で最小のもの
Function AXRD_NiceStep(raw)
	Variable raw
	if (!(raw > 0) || numtype(raw) != 0)
		return 1
	endif
	Variable mag = 10 ^ floor(log(raw))
	Variable f = raw / mag
	if (f <= 1)
		return mag
	elseif (f <= 2)
		return 2 * mag
	elseif (f <= 5)
		return 5 * mag
	endif
	return 10 * mag
End

// 既にある目盛りから tickGap 以上離れていれば、位置 yPos に値 val の目盛りを足す
Function AXRD_AddYTick(tp, tl, yPos, val, dec, tickGap)
	Wave tp
	Wave/T tl
	Variable yPos, val, dec, tickGap
	Variable i, n = numpnts(tp)
	for (i = 0; i < n; i += 1)
		if (abs(tp[i] - yPos) < tickGap)
			return 0
		endif
	endfor
	Variable sc = 10 ^ dec
	val = round(val * sc) / sc
	if (val == 0)
		val = 0		// "-0" と書かない
	endif
	String fmt = "%." + num2istr(dec) + "f"
	String txt
	sprintf txt, fmt, val
	Redimension/N=(n + 1) tp, tl
	tp[n] = yPos
	tl[n] = txt
	return 1
End

// Y が単調でないとき用の目盛り。image はスキャン順 (j 番目のスキャンが y = j + 1) に描き、
// 左軸には次の位置に Y の値を書く。文字が重なるほど近いものは省く (先に置いたものが優先)。
//   1) 最初・最後のスキャンと、最大・最小のスキャン (その値)
//   2) きりのよい値をまたぐ位置 (隣り合うスキャンの間を線形補間)
Function AXRD_MapMakeYTicks(sy)
	Wave sy
	DFREF mapDF = $kAXRD_MapDF
	Make/O/D/N=0 mapDF:yTickPos
	Make/O/T/N=0 mapDF:yTickLab
	Wave tp = mapDF:yTickPos
	Wave/T tl = mapDF:yTickLab
	Variable ns = numpnts(sy)
	if (ns < 1)
		return 0
	endif

	Variable j, jMin = 0, jMax = 0
	for (j = 1; j < ns; j += 1)
		if (sy[j] < sy[jMin])
			jMin = j
		endif
		if (sy[j] > sy[jMax])
			jMax = j
		endif
	endfor
	Variable tStep = AXRD_NiceStep((sy[jMax] - sy[jMin]) / 6)
	Variable dec = (tStep < 1) ? min(6, ceil(-log(tStep) - 1e-9)) : 0
	Variable tickGap = max(1, 0.06 * ns)		// 文字の高さ (軸の長さの約 6 %) ぶん

	AXRD_AddYTick(tp, tl, 1, sy[0], dec, tickGap)
	AXRD_AddYTick(tp, tl, ns, sy[ns - 1], dec, tickGap)
	AXRD_AddYTick(tp, tl, jMax + 1, sy[jMax], dec, tickGap)
	AXRD_AddYTick(tp, tl, jMin + 1, sy[jMin], dec, tickGap)

	Variable a, b, k1, k2, kk, v
	for (j = 0; j < ns - 1; j += 1)
		a = sy[j]
		b = sy[j + 1]
		if (a == b)
			continue
		endif
		k1 = ceil(min(a, b) / tStep - 1e-9)
		k2 = floor(max(a, b) / tStep + 1e-9)
		for (kk = k1; kk <= k2; kk += 1)
			v = (b > a) ? kk * tStep : (k1 + k2 - kk) * tStep		// 位置が増える順にたどる
			AXRD_AddYTick(tp, tl, j + 1 + (v - a) / (b - a), v, dec, tickGap)
		endfor
	endfor
	Sort tp, tp, tl
	return numpnts(tp)
End

// ----------------------------------------------------------------------------
//  温度ログ: XRD のファイル名と、その測定中の平均温度の対応表
// ----------------------------------------------------------------------------

// ログのファイル名欄 → 照合用のキー (フォルダと拡張子 .txt を外す)
Function/S AXRD_TLogKey(name)
	String name
	name = TrimString(name)
	Variable i = max(strsearch(name, "\\", inf, 1), strsearch(name, "/", inf, 1))
	if (i >= 0)
		name = name[i + 1, inf]
	endif
	if (StringMatch(name, "*.txt"))
		name = name[0, strlen(name) - 5]
	endif
	return name
End

// 温度ログを読み込む。"#" で始まる行は読み飛ばし、
// 「ファイル名 <タブまたはカンマ> 温度」の行だけを拾う。拾えた行数を返す (開けなければ -1)。
// 1 行も拾えなければ、読み込み済みのログはそのまま残す。
Function AXRD_LoadTLog(fullPath)
	String fullPath
	DFREF df = AXRD_ToolDF("Map")
	Variable refNum
	Open/R/Z refNum as fullPath
	if (V_flag != 0)
		return -1
	endif
	Make/FREE/T/N=256 keyW
	Make/FREE/D/N=256 tempW
	String lineStr, keyStr
	Variable n = 0, i, val
	do
		FReadLine refNum, lineStr
		if (strlen(lineStr) == 0)
			break		// end of file
		endif
		lineStr = ReplaceString("\r", lineStr, "")
		lineStr = ReplaceString("\n", lineStr, "")
		if (strlen(lineStr) == 0 || CmpStr(lineStr[0], "#") == 0)
			continue
		endif
		i = strsearch(lineStr, "\t", inf, 1)
		if (i < 0)
			i = strsearch(lineStr, ",", inf, 1)
		endif
		if (i <= 0)
			continue
		endif
		val = str2num(lineStr[i + 1, inf])
		keyStr = AXRD_TLogKey(lineStr[0, i - 1])
		if (numtype(val) != 0 || strlen(keyStr) == 0)
			continue
		endif
		if (n >= numpnts(keyW))
			Redimension/N=(2 * n) keyW, tempW
		endif
		keyW[n] = keyStr
		tempW[n] = val
		n += 1
	while (1)
	Close refNum
	if (n == 0)
		return 0
	endif
	Redimension/N=(n) keyW, tempW
	Duplicate/O keyW, df:tLogName
	Duplicate/O tempW, df:tLogT
	return n
End

// 読み込み済みの温度ログから、現在のマップの各スキャンの温度 (T_file) を引く。
// ファイル名 (拡張子なし) が一致した行を使う。見つからないスキャンは NaN。見つかった数を返す。
Function AXRD_MapFillTFile()
	DFREF df = AXRD_ToolDF("Map")
	DFREF mapDF = $kAXRD_MapDF
	SVAR gTFileDisp = df:gTFileDisp
	Wave/Z/T tLogName = df:tLogName
	Wave/Z tLogT = df:tLogT
	Wave/Z/T scanLabel = mapDF:scanLabel
	Variable nLog = 0
	if (WaveExists(tLogName) && WaveExists(tLogT))
		nLog = min(numpnts(tLogName), numpnts(tLogT))
	endif
	if (nLog == 0)
		gTFileDisp = "(no temperature file)"
	else
		sprintf gTFileDisp, "%d temperatures loaded", nLog
	endif
	if (!WaveExists(scanLabel))
		return 0
	endif

	Variable ns = numpnts(scanLabel), j, found = 0
	Make/O/D/N=(ns) mapDF:T_file = NaN
	Wave T_file = mapDF:T_file
	if (nLog == 0)
		return 0
	endif
	String keyStr
	for (j = 0; j < ns; j += 1)
		keyStr = scanLabel[j]
		FindValue/TEXT=keyStr/TXOP=4 tLogName
		if (V_value >= 0 && V_value < nLog)
			T_file[j] = tLogT[V_value]
			found += 1
		endif
	endfor
	sprintf gTFileDisp, "%d of %d scans matched", found, ns
	return found
End

// 温度ログを選んで読み込み、Y 軸を "Temperature (file)" に切り替える
Function AXRD_MapLoadTFile()
	DFREF df = AXRD_ToolDF("Map")
	SVAR gStatus = df:gStatus
	NVAR gYMode = df:gYMode
	NVAR gTUnit = df:gTUnit
	String pathName = AXRD_PathName("Map")
	String pn = kAXRD_MGraph + "#ctrl"
	String filters = "Text files (*.txt,*.csv,*.dat):.txt,.csv,.dat;All files:.*;"
	String msg = "Select the temperature log (XRD file name and mean temperature)"
	Variable refNum

	PathInfo $pathName
	if (V_flag)
		Open/D/R/F=filters/M=msg/P=$pathName refNum
	else
		Open/D/R/F=filters/M=msg refNum
	endif
	String fullPath = S_fileName
	if (strlen(fullPath) == 0)
		return -1		// cancelled
	endif

	Variable n = AXRD_LoadTLog(fullPath)
	if (n <= 0)
		gStatus = "No temperatures found in that file."
		return -1
	endif
	gYMode = 5
	gTUnit = 2		// ログの温度は °C
	PopupMenu popYMode, win=$pn, mode=5
	PopupMenu popUnit, win=$pn, mode=2
	sprintf gStatus, "T file: %d temperatures loaded.", n
	AXRD_MapFillTFile()
	AXRD_MapRefresh(1, 0)
	return n
End

// 2θ 範囲 [x1, x2] (x2 <= x1 なら全域) に対応する行番号の範囲
Function AXRD_MapPointRange(M, x1, x2, p1, p2)
	Wave M
	Variable x1, x2
	Variable &p1, &p2
	Variable nx = DimSize(M, 0)
	p1 = 0
	p2 = nx - 1
	if (x2 > x1)
		p1 = limit(round((x1 - DimOffset(M, 0)) / DimDelta(M, 0)), 0, nx - 1)
		p2 = limit(round((x2 - DimOffset(M, 0)) / DimDelta(M, 0)), 0, nx - 1)
		if (p2 <= p1)
			p1 = 0
			p2 = nx - 1
		endif
	endif
End

// 2θ 範囲 [x1, x2] 内 (x2 <= x1 なら全域) の最小・最大。有効点数を返す。
Function AXRD_MapRangeStats(M, x1, x2, positiveOnly, vmin, vmax)
	Wave M
	Variable x1, x2, positiveOnly
	Variable &vmin, &vmax
	Variable p1, p2
	AXRD_MapPointRange(M, x1, x2, p1, p2)
	Duplicate/FREE/R=[p1, p2][] M, sub
	if (positiveOnly)
		sub = (sub[p][q] > 0) ? sub[p][q] : NaN
	endif
	WaveStats/Q/M=1 sub
	vmin = V_min
	vmax = V_max
	return V_npnts
End

// image グラフ (と、あれば stack グラフ) を現在の設定に合わせる
//   applyAxes  : 1 で 2θ 範囲の設定を軸に反映
//   createStack: 1 で stack グラフが無ければ作る
Function AXRD_MapRefresh(applyAxes, createStack)
	Variable applyAxes, createStack
	DFREF df = AXRD_ToolDF("Map")
	DFREF mapDF = $kAXRD_MapDF
	Wave/Z M = mapDF:xrdMap
	Wave/Z scanNum = mapDF:scanNum
	String g = kAXRD_MGraph
	DoWindow $g
	if (!V_flag || !WaveExists(M) || !WaveExists(scanNum))
		return 0
	endif
	SVAR gCtabImg = df:gCtabImg
	NVAR gRevImg = df:gRevImg
	NVAR gLogImg = df:gLogImg
	NVAR gZAuto = df:gZAuto
	NVAR gZMin = df:gZMin
	NVAR gZMax = df:gZMax
	NVAR gX1 = df:gX1
	NVAR gX2 = df:gX2

	String yLab = "", imgYLab = "", tagFmt = ""
	Variable mono = AXRD_MapComputeY(yLab, imgYLab, tagFmt)
	Wave se = mapDF:scanYEdge

	if (WhichListItem("xrdMap", ImageNameList(g, ";")) < 0)
		AppendImage/W=$g M vs {*, se}
		ModifyGraph/W=$g gfSize=12, tick=2, mirror=1
		ColorScale/W=$g/C/N=axrdCS/F=0/B=1/A=RC/E image=xrdMap, heightPct=70, width=8, "Intensity / a.u."
		applyAxes = 1
	endif
	String xl = "\\Z16" + "2\\f02θ\\f00 / deg."
	String yl = "\\Z16" + imgYLab
	Label/W=$g bottom xl
	Label/W=$g left yl
	if (mono)
		ModifyGraph/W=$g userticks(left)=0
	else
		// スキャン順の image に、Y の値 (温度など) の目盛りを付ける
		Wave yTickPos = mapDF:yTickPos
		Wave/T yTickLab = mapDF:yTickLab
		ModifyGraph/W=$g userticks(left)={yTickPos, yTickLab}
	endif

	if (applyAxes)
		if (gX2 > gX1)
			SetAxis/W=$g bottom gX1, gX2
		else
			SetAxis/A/W=$g bottom
		endif
		SetAxis/A/W=$g left
	endif

	Variable vmin, vmax
	if (AXRD_MapRangeStats(M, gX1, gX2, gLogImg, vmin, vmax) > 0)
		if (gZAuto)
			gZMax = vmax
			gZMin = gLogImg ? max(vmin, vmax / 1000) : vmin
		endif
	endif
	Variable zmin = gZMin, zmax = gZMax
	if (gLogImg && !(zmin > 0))
		zmin = zmax / 1000
	endif
	ModifyImage/W=$g xrdMap ctab={zmin, zmax, $gCtabImg, gRevImg}, log=(gLogImg != 0)
	ColorScale/W=$g/C/N=axrdCS log=(gLogImg != 0)

	AXRD_StackRefresh(applyAxes, createStack, yLab, tagFmt)
	return 1
End

// 縦オフセット付きプロファイル
Function AXRD_StackRefresh(applyAxes, create, yLab, tagFmt)
	Variable applyAxes, create
	String yLab, tagFmt
	DFREF df = AXRD_ToolDF("Map")
	DFREF mapDF = $kAXRD_MapDF
	Wave/Z M = mapDF:xrdMap
	Wave/Z sy = mapDF:scanY
	if (!WaveExists(M) || !WaveExists(sy))
		return 0
	endif
	SVAR gCtabStk = df:gCtabStk
	NVAR gRevStk = df:gRevStk
	NVAR gOffsetPct = df:gOffsetPct
	NVAR gEvery = df:gEvery
	NVAR gLabels = df:gLabels
	NVAR gX1 = df:gX1
	NVAR gX2 = df:gX2

	String g = kAXRD_SGraph
	DoWindow $g
	if (!V_flag)
		if (!create)
			return 0
		endif
		// image グラフの右隣に置く。画面に収まらなければ少しずらして重ねる
		Variable winL = kAXRD_PanelW + 80, winT = 110
		DoWindow $kAXRD_MGraph
		if (V_flag)
			DoUpdate/W=$kAXRD_MGraph		// 倍率変更後のウィンドウサイズを確定させる
			GetWindow $kAXRD_MGraph wsize
			if (V_right + 10 + 720 <= AXRD_ScreenWidth())
				winL = V_right + 10
				winT = V_top
			else
				winL = V_left + 40
				winT = V_top + 40
			endif
		endif
		Display/K=1/N=$g/W=(winL, winT, winL + 360, winT + 320) as "BL5S2 XRD - Stacked Profiles"
		ModifyGraph/W=$g expand=2
		applyAxes = 1
	endif

	Variable ns = DimSize(M, 1), j, k, i
	Variable every = max(1, round(gEvery))
	// stackPad: 表示しないがオートスケールには効くトレース。ラベルが上端で切れないよう余白を作る
	Make/O/D/N=2 mapDF:stackPad
	Wave pad = mapDF:stackPad
	SetScale/I x, DimOffset(M, 0), DimOffset(M, 0) + (DimSize(M, 0) - 1) * DimDelta(M, 0), "", pad
	pad = NaN

	String want = "", tn
	for (j = 0; j < ns; j += every)
		want += "s" + num2istr(j) + ";"
	endfor
	want += "pad;"
	String have = TraceNameList(g, ";", 1)
	if (CmpStr(have, want) != 0)
		for (i = ItemsInList(have) - 1; i >= 0; i -= 1)
			tn = StringFromList(i, have)
			RemoveFromGraph/W=$g $tn
		endfor
		for (j = 0; j < ns; j += every)
			tn = "s" + num2istr(j)
			AppendToGraph/W=$g M[][j]/TN=$tn
		endfor
		AppendToGraph/W=$g pad/TN=pad
		ModifyGraph/W=$g hideTrace(pad)=2
		AXRD_ApplyProfileStyle(g)
		applyAxes = 1
	endif

	if (applyAxes)
		if (gX2 > gX1)
			SetAxis/W=$g bottom gX1, gX2
		else
			SetAxis/A/W=$g bottom
		endif
		SetAxis/A/W=$g left
	endif

	Variable vmin, vmax
	if (AXRD_MapRangeStats(M, gX1, gX2, 0, vmin, vmax) == 0)
		vmax = 1
	endif
	Wave cw = AXRD_ColorWave(gCtabStk)
	Variable ymin = WaveMin(sy), ymax = WaveMax(sy)
	Variable row, frac, off

	// ラベルはプロット右端、各プロファイルのベースライン (中央値) の高さに描く。
	// データ点に付けるとピークの上に乗って隣のラベルと重なるため。
	Variable p1, p2, baseY, labelTop = -inf
	AXRD_MapPointRange(M, gX1, gX2, p1, p2)
	SetDrawLayer/W=$g/K UserFront

	String txt
	k = 0
	for (j = 0; j < ns; j += every)
		tn = "s" + num2istr(j)
		off = k * gOffsetPct / 100 * vmax
		if (ymax > ymin)
			frac = (sy[j] - ymin) / (ymax - ymin)
		else
			frac = (ns > 1) ? j / (ns - 1) : 0
		endif
		row = AXRD_ColorRow(cw, frac, gRevStk)
		ModifyGraph/W=$g offset($tn)={0, off}
		ModifyGraph/W=$g rgb($tn)=(cw[row][0], cw[row][1], cw[row][2])
		if (gLabels)
			Make/FREE/D/N=(p2 - p1 + 1) prof
			prof = M[p + p1][j]
			WaveTransform/O zapNaNs prof
			baseY = (numpnts(prof) > 0) ? median(prof) : 0
			sprintf txt, tagFmt, sy[j]
			SetDrawEnv/W=$g xcoord=prel, ycoord=left, textxjust=2, textyjust=0, fsize=12
			DrawText/W=$g 0.99, off + baseY, txt
			labelTop = max(labelTop, off + baseY)
		endif
		k += 1
	endfor
	if (gLabels && k > 0)
		// 文字 1 行ぶん (全体の高さの約 7 %) を最上段ラベルの上に確保する
		pad = labelTop + 0.07 * (abs((k - 1) * gOffsetPct / 100 * vmax) + vmax - vmin)
	endif

	if (ymax > ymin)
		if (WhichListItem("axrdCS", AnnotationList(g)) >= 0)
			ColorScale/W=$g/C/N=axrdCS ctab={ymin, ymax, $gCtabStk, gRevStk}, yLab
		else
			ColorScale/W=$g/C/N=axrdCS/F=0/B=1/A=RC/E heightPct=70, width=8, ctab={ymin, ymax, $gCtabStk, gRevStk}, yLab
		endif
	else
		AXRD_KillAnnotation(g, "axrdCS")
	endif
	return 1
End

Function AXRD_MapEditTable()
	DFREF df = AXRD_ToolDF("Map")
	DFREF mapDF = $kAXRD_MapDF
	SVAR gStatus = df:gStatus
	NVAR gYMode = df:gYMode
	Wave/Z/T scanLabel = mapDF:scanLabel
	Wave/Z scanNum = mapDF:scanNum
	Wave/Z T_user = mapDF:T_user
	if (!WaveExists(scanLabel) || !WaveExists(scanNum) || !WaveExists(T_user))
		gStatus = "Build the map first."
		return -1
	endif
	DoWindow/F AXRD_TTable
	if (!V_flag)
		Edit/K=1/N=AXRD_TTable/W=(60, 120, 520, 520) scanLabel, scanNum, T_user as "Temperature table (fill in T_user)"
		ModifyTable/W=AXRD_TTable width(scanLabel)=230
	endif
	gYMode = 4
	String pn = kAXRD_MGraph + "#ctrl"
	PopupMenu popYMode, win=$pn, mode=4
	gStatus = "Fill in T_user, then press Build Map or change any setting."
	return 0
End

Function AXRD_MButtonProc(ba) : ButtonControl
	STRUCT WMButtonAction &ba
	if (ba.eventCode != 2)
		return 0
	endif
	DFREF df = AXRD_ToolDF("Map")
	Wave selW = df:selW
	NVAR gX1 = df:gX1
	NVAR gX2 = df:gX2
	strswitch (ba.ctrlName)
		case "btnOpen":
			if (AXRD_ChooseFolder("Map") == 0)
				AXRD_MapFolderOpened()
			endif
			break
		case "btnRescan":
			AXRD_MapScanSeries()
			AXRD_MapSyncSeriesPopup()
			AXRD_Rescan("Map")
			break
		case "btnAll":
			selW = 1
			break
		case "btnNone":
			selW = 0
			break
		case "btnBuild":
			AXRD_MapBuild()
			break
		case "btnEditT":
			AXRD_MapEditTable()
			break
		case "btnLoadT":
			AXRD_MapLoadTFile()
			break
		case "btnFullX":
			gX1 = 0
			gX2 = 0
			AXRD_MapRefresh(1, 0)
			break
		case "btnStack":
			AXRD_MapRefresh(0, 1)
			DoWindow/F $kAXRD_SGraph
			break
	endswitch
	return 0
End

Function AXRD_MPopupProc(pa) : PopupMenuControl
	STRUCT WMPopupAction &pa
	if (pa.eventCode != 2)
		return 0
	endif
	DFREF df = AXRD_ToolDF("Map")
	strswitch (pa.ctrlName)
		case "popSeries":
			SVAR gSeries = df:gSeries
			Wave selW = df:selW
			gSeries = AXRD_SeriesFromPopStr(pa.popStr)
			selW = 0
			AXRD_Rescan("Map")
			if (strlen(gSeries) > 0)
				selW = 1
			endif
			break
		case "popYMode":
			NVAR gYMode = df:gYMode
			gYMode = pa.popNum
			AXRD_MapRefresh(1, 0)
			break
		case "popUnit":
			NVAR gTUnit = df:gTUnit
			gTUnit = pa.popNum
			AXRD_MapRefresh(0, 0)
			break
		case "popCtabImg":
			SVAR gCtabImg = df:gCtabImg
			gCtabImg = pa.popStr
			AXRD_MapRefresh(0, 0)
			break
		case "popCtabStk":
			SVAR gCtabStk = df:gCtabStk
			gCtabStk = pa.popStr
			AXRD_MapRefresh(0, 0)
			break
	endswitch
	return 0
End

Function AXRD_MCheckProc(cba) : CheckBoxControl
	STRUCT WMCheckboxAction &cba
	if (cba.eventCode == 2)
		AXRD_MapRefresh(0, 0)
	endif
	return 0
End

Function AXRD_MSetVarProc(sva) : SetVariableControl
	STRUCT WMSetVariableAction &sva
	if (sva.eventCode != 1 && sva.eventCode != 2)
		return 0
	endif
	DFREF df = AXRD_ToolDF("Map")
	NVAR gZAuto = df:gZAuto
	strswitch (sva.ctrlName)
		case "svZMin":
		case "svZMax":
			gZAuto = 0		// 手で入れたら自動を外す
			AXRD_MapRefresh(0, 0)
			break
		case "svX1":
		case "svX2":
			AXRD_MapRefresh(1, 0)
			break
		case "svT0":
		case "svTStep":
			AXRD_MapRefresh(1, 0)
			break
		default:
			AXRD_MapRefresh(0, 0)
			break
	endswitch
	return 0
End
