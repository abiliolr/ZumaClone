using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/UI }
using { /Verse.org/Simulation }
using { /Verse.org/Random }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }

# --- ESTRUTURAS DE DADOS ---
dados_da_bola := class:
    Prop : creative_prop
    Cor : int
    Id : int
    var DistanciaNaTrilha : float
    Tipo : int # 0=Normal, 1=Bomba, 2=Slow, 3=Reverso

segmento_trilha := struct:
    PontoA : vector3
    PontoB : vector3
    DistanciaInicio : float
    Comprimento : float
    Rotacao : rotation

config_fase := struct<concrete>:
    @editable Waypoints : []creative_prop = array{}
    @editable Gerador : player_spawner_device = player_spawner_device{}
    @editable CameraDaFase : gameplay_camera_fixed_point_device = gameplay_camera_fixed_point_device{}

# --- GERENCIADOR PRINCIPAL ---
zumba_advanced_manager := class(creative_device):

    # --- CONFIGURAÇÕES NO EDITOR ---
    @editable ListaDeFases : []config_fase = array{}

    # --- MODELOS ---
    @editable ModelosDeBolas : []creative_prop_asset = array{}
    @editable ModelosBomba : []creative_prop_asset = array{}
    @editable ModelosSlow : []creative_prop_asset = array{}
    @editable ModelosReverso : []creative_prop_asset = array{}

    @editable ModeloExplosao : creative_prop_asset = DefaultCreativePropAsset

    # --- CONFIGURAÇÃO DOS POWER-UPS ---
    @editable ChanceDePowerUp : int = 15
    @editable RaioDaExplosaoBomba : int = 4
    @editable DuracaoDoSlowMotion : float = 5.0
    @editable ForcaDoSlowMotion : float = 0.15
    @editable DuracaoDoReverso : float = 3.0
    @editable VelocidadeReverso : float = 200.0

    # --- ÁUDIO ---
    @editable SomDisparo : audio_player_device = audio_player_device{}
    @editable SomImpacto : audio_player_device = audio_player_device{}
    @editable SomExplosao : audio_player_device = audio_player_device{}
    # Array de sons para combos progressivos (ex: Pitch 1.0, 1.2, 1.4...)
    @editable SonsCombo : []audio_player_device = array{}

    @editable SomExplosaoBomba : audio_player_device = audio_player_device{}
    @editable SomAtivarSlow : audio_player_device = audio_player_device{}
    @editable SomAtivarReverso : audio_player_device = audio_player_device{}
    @editable SomGameOver : audio_player_device = audio_player_device{}
    @editable SomVitoria : audio_player_device = audio_player_device{}

    # --- VISUAL E FÍSICA ---
    @editable EscalaGlobal : vector3 = vector3{X:=3.0, Y:=3.0, Z:=3.0}
    @editable DiametroDaBola : float = 300.0
    @editable RaioDeColisao : float = 280.0

    @editable VelocidadeDaCobra : float = 150.0
    @editable VelocidadeDeRetorno : float = 3000.0 # Aumentado para 3000 (aprox 300ms para fechar gap de 3 bolas)
    @editable NumeroInicialDeBolas : int = 15

    @editable DistanciaDePerigo : float = 2000.0
    @editable MultiplicadorLentidao : float = 0.4

    @editable SetaDeMira : creative_prop = creative_prop{}
    @editable OffsetDaMira : vector3 = vector3{X:=0.0, Y:=0.0, Z:=10.0}
    @editable OffsetDaBoca : vector3 = vector3{X:=80.0, Y:=0.0, Z:=50.0}
    @editable InclinacaoDaSeta : float = 0.0
    @editable GiroDaSeta : float = 0.0

    @editable GatilhoDeTiro : input_trigger_device = input_trigger_device{}
    @editable DispositivoFimDeJogo : end_game_device = end_game_device{}
    @editable DispositivoVitoria : end_game_device = end_game_device{}

    # Dispositivos de Accolades para XP Progressivo
    # Index 0 = Normal, Index 1 = Combo 1, Index 2 = Combo 2, etc.
    @editable ListaDeXP : []accolades_device = array{}

    @editable VelocidadeDoTiro : float = 1500.0

    # --- VARIÁVEIS INTERNAS ---
    var Cobra : []dados_da_bola = array{}
    var MapaDaTrilha : []segmento_trilha = array{}
    var ComprimentoTotalTrilha : float = 0.0

    var ContadorDeIds : int = 0
    var BolaNaBoca : ?creative_prop = false
    var IndiceDaCorAtual : int = 0

    var JogoRodando : logic = false
    var ProcessandoExplosao : logic = false

    var IndiceFaseAtual : int = 0
    var BolasRestantesParaSpawnar : int = 0

    var NumCoresAtivas : int = 3
    var VelocidadeAtualFase : float = 150.0

    # Variáveis da Intro
    var ModoIntro : logic = false
    var VelocidadeIntro : float = 2000.0

    var MenuAberto : ?canvas = false

    var TempoRestanteSlow : float = 0.0
    var TempoRestanteReverso : float = 0.0

    # Sistema de Combo
    var NivelDoCombo : int = 0

    # Textos de UI
    TextoTitulo<localizes> : message = "ZUMA GAME"
    TextoInstrucao<localizes> : message = "ATIRE PARA INICIAR"

    TextoGameOver<localizes> : message = "GAME OVER"
    TextoVitoriaTitulo<localizes> : message = "VOCÊ VENCEU!"
    TextoVitoriaDesc<localizes> : message = "Parabéns! Mais fases em breve."
    TextoBotaoReset<localizes> : message = "TENTAR NOVAMENTE"
    TextoBotaoJogarNovamente<localizes> : message = "REINICIAR JOGO"

    # --- FUNÇÃO AUXILIAR ---
    GetRandomIntSafe(MinVal : int, MaxVal : int)<transacts>:int=
        MaybeInt := option{GetRandomInt(MinVal, MaxVal)}
        if (Val := MaybeInt?):
            return Val
        return MinVal

    # --- INÍCIO ---
    OnBegin<override>()<suspends>:void=
        if (ListaDeFases.Length = 0):
            return

        LimparEstadoInicial()

        GatilhoDeTiro.PressedEvent.Subscribe(AoPressionarGatilho)

        spawn{ LoopDaMira() }
        spawn{ LoopMovimentoCobra() }

        MostrarTelaInicial()

    LimparEstadoInicial():void=
        if (Player := GetPlayspace().GetPlayers()[0]):
            if (FC := Player.GetFortCharacter[]):
                FC.ReleaseFromStasis()
            for (Fase : ListaDeFases):
                Fase.CameraDaFase.RemoveFrom(Player)

    # --- UI INICIAL ---
    MostrarTelaInicial():void=
        if (Player := GetPlayspace().GetPlayers()[0]):
            Titulo := text_block{DefaultText := TextoTitulo, DefaultTextColor := NamedColors.Yellow, DefaultJustification := text_justification.Center}
            Instrucao := text_block{DefaultText := TextoInstrucao, DefaultTextColor := NamedColors.White, DefaultJustification := text_justification.Center}

            BotaoStart := button_loud{ DefaultText := TextoInstrucao }
            BotaoStart.OnClick().Subscribe(AoClicarBotaoUI)

            TelaMenu := canvas:
                Slots := array:
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X:=0.5, Y:=0.4}, Maximum := vector2{X:=0.5, Y:=0.4}}
                        Alignment := vector2{X:=0.5, Y:=0.5}
                        Widget := Titulo
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X:=0.5, Y:=0.6}, Maximum := vector2{X:=0.5, Y:=0.6}}
                        Alignment := vector2{X:=0.5, Y:=0.5}
                        Widget := BotaoStart

            if (PlayerUI := GetPlayerUI[Player]):
                PlayerUI.AddWidget(TelaMenu)
                set MenuAberto = option{TelaMenu}

    # --- UI DE FIM DE JOGO ---
    MostrarMenuFimDeJogo(Venceu : logic):void=
        if (Player := GetPlayspace().GetPlayers()[0]):

            var TextoPrincipal : message = TextoGameOver
            var TextoDescricao : message = TextoBotaoReset
            var CorTexto : color = NamedColors.Red

            if (Venceu?):
                set TextoPrincipal = TextoVitoriaTitulo
                set TextoDescricao = TextoVitoriaDesc
                set CorTexto = NamedColors.Green

            Titulo := text_block{DefaultText := TextoPrincipal, DefaultTextColor := CorTexto, DefaultJustification := text_justification.Center}
            Desc := text_block{DefaultText := TextoDescricao, DefaultTextColor := NamedColors.White, DefaultJustification := text_justification.Center}

            BotaoReset := button_loud{ DefaultText := TextoBotaoReset }
            if (Venceu?):
                BotaoReset.SetText(TextoBotaoJogarNovamente)

            BotaoReset.OnClick().Subscribe(AoClicarBotaoUI)

            TelaFim := canvas:
                Slots := array:
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X:=0.5, Y:=0.3}, Maximum := vector2{X:=0.5, Y:=0.3}}
                        Alignment := vector2{X:=0.5, Y:=0.5}
                        Widget := Titulo
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X:=0.5, Y:=0.4}, Maximum := vector2{X:=0.5, Y:=0.4}}
                        Alignment := vector2{X:=0.5, Y:=0.5}
                        Widget := Desc
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X:=0.5, Y:=0.6}, Maximum := vector2{X:=0.5, Y:=0.6}}
                        Alignment := vector2{X:=0.5, Y:=0.5}
                        Widget := BotaoReset

            if (PlayerUI := GetPlayerUI[Player]):
                PlayerUI.AddWidget(TelaFim)
                set MenuAberto = option{TelaFim}

                if (FC := Player.GetFortCharacter[]):
                    FC.PutInStasis(stasis_args{AllowTurning:=false, AllowFalling:=false, AllowEmotes:=false})

    AoClicarBotaoUI(Widget : widget_message):void=
        IniciarJogo(Widget.Player)

    AoPressionarGatilho(Agente : agent):void=
        if (JogoRodando?):
            if (not ModoIntro?):
                spawn{ AtirarBola() }
        else:
            IniciarJogo(Agente)

    IniciarJogo(Agente : agent):void=
        if (PlayerUI := GetPlayerUI[player[Agente]], MenuParaRemover := MenuAberto?):
            PlayerUI.RemoveWidget(MenuParaRemover)
            set MenuAberto = false

        if (P := player[Agente], FC := P.GetFortCharacter[]):
            FC.ReleaseFromStasis()

        CarregarFase(0)

    # --- FASES ---
    CarregarFase(Indice : int):void=
        if (Indice >= ListaDeFases.Length):
            Print("VITÓRIA FINAL!")
            if (P := GetPlayspace().GetPlayers()[0]):
                SomVitoria.Play(P)
                if (P_FC := P.GetFortCharacter[]):
                     if (SomVitoria.TeleportTo[P_FC.GetTransform()]) {}

            MostrarMenuFimDeJogo(true)
            return

        if (FaseData := ListaDeFases[Indice]):
            if (Player := GetPlayspace().GetPlayers()[0]):
                if (FaseAnterior := ListaDeFases[IndiceFaseAtual]):
                    FaseAnterior.CameraDaFase.RemoveFrom(Player)

            set IndiceFaseAtual = Indice
            NumeroFase := Indice + 1
            Print("--- INICIANDO FASE {NumeroFase} ---")

            if (NumeroFase <= 5):
                set BolasRestantesParaSpawnar = GetRandomIntSafe(60, 70)
                set NumCoresAtivas = 3
                set VelocidadeAtualFase = 150.0

            else if (NumeroFase <= 10):
                set BolasRestantesParaSpawnar = GetRandomIntSafe(80, 100)
                set NumCoresAtivas = 4
                set VelocidadeAtualFase = 180.0

            else if (NumeroFase <= 15):
                set BolasRestantesParaSpawnar = GetRandomIntSafe(100, 120)
                set NumCoresAtivas = 5
                set VelocidadeAtualFase = 210.0

            else:
                set BolasRestantesParaSpawnar = GetRandomIntSafe(120, 130)
                set NumCoresAtivas = 6
                set VelocidadeAtualFase = 250.0

            if (NumCoresAtivas > ModelosDeBolas.Length):
                set NumCoresAtivas = ModelosDeBolas.Length

            Print("Fase {NumeroFase}: {BolasRestantesParaSpawnar} Bolas | {NumCoresAtivas} Cores")

            LimparCobraExistente()
            set MapaDaTrilha = array{}
            set Cobra = array{}
            set TempoRestanteSlow = 0.0
            set TempoRestanteReverso = 0.0
            set NivelDoCombo = 0

            set ModoIntro = true

            if (P := GetPlayspace().GetPlayers()[0], FC := P.GetFortCharacter[]):
                TransformGerador := FaseData.Gerador.GetTransform()
                PosicaoComAltura := TransformGerador.Translation + vector3{X:=0.0, Y:=0.0, Z:=100.0}

                FC.ReleaseFromStasis()

                if (FC.TeleportTo[PosicaoComAltura, TransformGerador.Rotation]) {}
                if (SetaDeMira.TeleportTo[PosicaoComAltura + OffsetDaMira, TransformGerador.Rotation]) {}

                if (SomDisparo.TeleportTo[PosicaoComAltura, TransformGerador.Rotation]) {}
                if (SomImpacto.TeleportTo[PosicaoComAltura, TransformGerador.Rotation]) {}
                if (SomExplosao.TeleportTo[PosicaoComAltura, TransformGerador.Rotation]) {}
                if (SomExplosaoBomba.TeleportTo[PosicaoComAltura, TransformGerador.Rotation]) {}
                if (SomAtivarSlow.TeleportTo[PosicaoComAltura, TransformGerador.Rotation]) {}
                if (SomAtivarReverso.TeleportTo[PosicaoComAltura, TransformGerador.Rotation]) {}
                if (SomGameOver.TeleportTo[PosicaoComAltura, TransformGerador.Rotation]) {}
                if (SomVitoria.TeleportTo[PosicaoComAltura, TransformGerador.Rotation]) {}

                FaseData.CameraDaFase.AddTo(P)

            CalcularGeometriaDaTrilha(FaseData.Waypoints)
            spawn{ IniciarLogicaAposDelay() }

    IniciarLogicaAposDelay()<suspends>:void=
        Sleep(0.5)
        set JogoRodando = true
        Recarregar()
        GerarCobraInicial()

    LimparCobraExistente():void=
        for (Bola : Cobra):
            Bola.Prop.Dispose()
        set Cobra = array{}
        if (B := BolaNaBoca?):
            B.Dispose()
            set BolaNaBoca = false

    ChecarVitoria()<suspends>:void=
        if (Cobra.Length = 0 and BolasRestantesParaSpawnar <= 0):
            set JogoRodando = false
            Sleep(2.0)
            CarregarFase(IndiceFaseAtual + 1)

    AtivarGameOver():void=
        if (JogoRodando?):
            set JogoRodando = false
            Print("GAME OVER!")

            if (P := GetPlayspace().GetPlayers()[0]):
                SomGameOver.Play(P)
                if (P_FC := P.GetFortCharacter[]):
                     if (SomGameOver.TeleportTo[P_FC.GetTransform()]) {}

            MostrarMenuFimDeJogo(false)

    # --- MATEMÁTICA ---
    CalcularGeometriaDaTrilha(WaypointsDaFase : []creative_prop):void=
        var DistanciaAcumulada : float = 0.0
        set MapaDaTrilha = array{}

        if (WaypointsDaFase.Length < 2):
            return

        for (I := 0..WaypointsDaFase.Length - 2):
            if (PontoA := WaypointsDaFase[I], PontoB := WaypointsDaFase[I+1]):
                PosA := PontoA.GetTransform().Translation
                PosB := PontoB.GetTransform().Translation
                Dist := Distance(PosA, PosB)
                Rot := PontoA.GetTransform().Rotation
                NovoSegmento := segmento_trilha{
                    PontoA := PosA, PontoB := PosB, DistanciaInicio := DistanciaAcumulada, Comprimento := Dist, Rotacao := Rot
                }
                set MapaDaTrilha += array{NovoSegmento}
                set DistanciaAcumulada += Dist
        set ComprimentoTotalTrilha = DistanciaAcumulada

    # --- LOOP COBRA ---
    LoopMovimentoCobra()<suspends>:void=
        FPS := 30.0
        Passo := 1.0 / FPS
        loop:
            Sleep(Passo)
            if (JogoRodando = false):
                Sleep(0.1)
            else:
                # 1. Determinar Velocidade da Cauda (Engine)
                var VelocidadeCauda : float = VelocidadeAtualFase

                if (ModoIntro?):
                    set VelocidadeCauda = VelocidadeIntro
                else:
                    if (TempoRestanteReverso > 0.0):
                        set VelocidadeCauda = -VelocidadeReverso
                        set TempoRestanteReverso -= Passo
                    else if (TempoRestanteSlow > 0.0):
                        set VelocidadeCauda = VelocidadeAtualFase * ForcaDoSlowMotion
                        set TempoRestanteSlow -= Passo
                    else:
                        if (Cobra.Length > 0, C := Cobra[0]):
                            DistRestante := ComprimentoTotalTrilha - C.DistanciaNaTrilha
                            if (DistRestante < DistanciaDePerigo):
                                set VelocidadeCauda = VelocidadeAtualFase * MultiplicadorLentidao

                if (Cobra.Length > 0):
                    # 2. Mover a Cauda (Último elemento do array, que empurra o resto)
                    UltimoIdx := Cobra.Length - 1
                    if (UltimaBola := Cobra[UltimoIdx]):
                        set UltimaBola.DistanciaNaTrilha += VelocidadeCauda * Passo

                    # 3. Propagar movimento da Cauda para a Cabeça (Trás para Frente)
                    # Isso permite gaps, conexões e atração (recuo)
                    var VelocidadeTras : float = VelocidadeCauda

                    var I : int = UltimoIdx - 1
                    loop:
                        if (I < 0) { break }

                        if (BolaFrente := Cobra[I], BolaTras := Cobra[I+1]):
                            # Verifica distância atual (Nota: BolaTras já se moveu neste frame)
                            DistAtual := BolaFrente.DistanciaNaTrilha - BolaTras.DistanciaNaTrilha
                            var VelocidadeFrente : float = 0.0

                            # Se estão conectados (ou muito perto), BolaFrente herda a velocidade de quem empurra
                            # Adicionamos tolerância de 5.0 para manter coesão
                            if (DistAtual <= DiametroDaBola + 5.0):
                                set VelocidadeFrente = VelocidadeTras
                            else:
                                # Existe um Gap. Verificar Atração (Match de Cores) ou Reverso
                                # Lógica Melhorada: Se houver match, atrai (-Retorno).
                                # Se não houver match mas o segmento de trás estiver recuando (Powerup Reverso),
                                # o segmento da frente deve acompanhar para manter a formação (arrasto).

                                if (BolaFrente.Cor = BolaTras.Cor and not ModoIntro?):
                                    set VelocidadeFrente = -VelocidadeDeRetorno
                                else if (VelocidadeTras < 0.0):
                                    set VelocidadeFrente = VelocidadeTras # Arrasta para trás junto com o Reverso
                                else:
                                    # Sem match e sem reverso, a bola da frente para
                                    set VelocidadeFrente = 0.0

                            # Aplica o movimento
                            set BolaFrente.DistanciaNaTrilha += VelocidadeFrente * Passo

                            # 4. Resolver Colisões (Fechar Gaps e Snapping)
                            NovaDist := BolaFrente.DistanciaNaTrilha - BolaTras.DistanciaNaTrilha
                            if (NovaDist < DiametroDaBola):
                                # Colisão: Snap na posição correta
                                set BolaFrente.DistanciaNaTrilha = BolaTras.DistanciaNaTrilha + DiametroDaBola

                                # DETECÇÃO DE COMBO POR ATRAÇÃO:
                                # Se a bola da frente estava recuando (Atração) e bateu na de trás, verificar combo.
                                if (VelocidadeFrente < -1.0 and not ProcessandoExplosao?):
                                     # É um combo automático (cadeia)
                                     # FIX: Captura de variavel para spawn
                                     IndiceCapturado := I
                                     spawn{ VerificarEExplodirSeguro(IndiceCapturado, BolaFrente.Cor, true) }

                                # Ao colidir, assume a velocidade de trás para o próximo frame (ou propagação)
                                set VelocidadeFrente = VelocidadeTras

                            set VelocidadeTras = VelocidadeFrente

                        set I -= 1

                    # --- GAME OVER E VISUAL ---
                    if (Cabeca := Cobra[0]):
                        if (Cabeca.DistanciaNaTrilha >= ComprimentoTotalTrilha):
                            AtivarGameOver()

                    for (Bola : Cobra):
                        if (Bola.DistanciaNaTrilha >= 0.0):
                            if (Bola.DistanciaNaTrilha <= ComprimentoTotalTrilha):
                                T := ObterTransformNaTrilha(Bola.DistanciaNaTrilha)
                                if (Bola.Prop.TeleportTo[T]) {}
                else:
                    spawn{ ChecarVitoria() }

    # --- MIRA ---
    LoopDaMira()<suspends>:void=
        loop:
            Sleep(0.0)
            if (P := GetPlayspace().GetPlayers()[0], FC := P.GetFortCharacter[]):
                T := FC.GetTransform()
                Rot := T.Rotation.ApplyLocalRotationZ(DegreesToRadians(GiroDaSeta)).ApplyLocalRotationY(DegreesToRadians(InclinacaoDaSeta))
                Pos := T.Translation + OffsetDaMira

                if (SetaDeMira.TeleportTo[Pos, Rot]) {}

                if (BV := BolaNaBoca?):
                     PosB := Pos + (Rot.GetLocalForward()*OffsetDaBoca.X) + (Rot.GetLocalUp()*OffsetDaBoca.Z) + (Rot.GetLocalRight()*OffsetDaBoca.Y)
                     TransformBoca := transform{Translation:=PosB, Rotation:=Rot, Scale:=EscalaGlobal}
                     if (BV.TeleportTo[TransformBoca]) {}

    ObterTransformNaTrilha(Distancia : float)<transacts>:transform=
        for (Seg : MapaDaTrilha):
            if (Distancia >= Seg.DistanciaInicio and Distancia < (Seg.DistanciaInicio + Seg.Comprimento)):
                DistanciaLocal := Distancia - Seg.DistanciaInicio
                Porcentagem := DistanciaLocal / Seg.Comprimento
                VetorDirecao := Seg.PontoB - Seg.PontoA
                PosicaoFinal := Seg.PontoA + (VetorDirecao * Porcentagem)
                return transform{ Translation := PosicaoFinal, Rotation := Seg.Rotacao, Scale := EscalaGlobal }
        if (Ultimo := MapaDaTrilha[MapaDaTrilha.Length - 1]):
            return transform{ Translation := Ultimo.PontoB, Rotation := Ultimo.Rotacao, Scale := EscalaGlobal }
        return transform{}

    # --- SPAWN (TOTAL NA INTRO) ---
    GerarCobraInicial()<suspends>:void=
        loop:
            if (BolasRestantesParaSpawnar <= 0):
                break

            Sleep(0.08) # Velocidade Rapida de Spawn
            AdicionarBolaNaCobra()
            set BolasRestantesParaSpawnar -= 1

        # Estabilizacao da fisica
        Sleep(1.0)
        set ModoIntro = false

    AdicionarBolaNaCobra():void=
        Cor := GetRandomIntSafe(0, NumCoresAtivas - 1)

        var TipoBola : int = 0
        Chance := GetRandomIntSafe(1, 100)

        if (Chance <= ChanceDePowerUp):
            SorteioTipo := GetRandomIntSafe(0, 2)
            if (SorteioTipo = 0):
                set TipoBola = 1
            else if (SorteioTipo = 1):
                set TipoBola = 2
            else:
                set TipoBola = 3

        var ModeloParaSpawnar : ?creative_prop_asset = false

        if (TipoBola = 0):
            if (M := ModelosDeBolas[Cor]):
                set ModeloParaSpawnar = option{M}
        else if (TipoBola = 1):
            if (M := ModelosBomba[Cor]):
                set ModeloParaSpawnar = option{M}
            else if (M := ModelosDeBolas[Cor]):
                set ModeloParaSpawnar = option{M}
        else if (TipoBola = 2):
            if (M := ModelosSlow[Cor]):
                set ModeloParaSpawnar = option{M}
            else if (M := ModelosDeBolas[Cor]):
                set ModeloParaSpawnar = option{M}
        else if (TipoBola = 3):
            if (M := ModelosReverso[Cor]):
                set ModeloParaSpawnar = option{M}
            else if (M := ModelosDeBolas[Cor]):
                set ModeloParaSpawnar = option{M}

        if (Modelo := ModeloParaSpawnar?):
            PosZero := vector3{X:=0.0, Y:=0.0, Z:=-5000.0}
            Result := SpawnProp(Modelo, PosZero, rotation{})
            if (NovaBola := Result(0)?):
                TransformInicial := transform{Translation:=PosZero, Rotation:=rotation{}, Scale:=EscalaGlobal}
                if (NovaBola.TeleportTo[TransformInicial]) {}

                set ContadorDeIds += 1
                var DistanciaInicial : float = 0.0
                if (UltimaBola := Cobra[Cobra.Length - 1]):
                    set DistanciaInicial = UltimaBola.DistanciaNaTrilha - DiametroDaBola

                NovaEstrutura := dados_da_bola{
                    Prop := NovaBola, Cor := Cor, Id := ContadorDeIds, DistanciaNaTrilha := DistanciaInicial, Tipo := TipoBola
                }
                set Cobra += array{NovaEstrutura}

    # --- TIRO E RECARGA ---
    Recarregar():void=
        var CoresPresentes : []int = array{}

        for (Bola : Cobra):
            var JaTem : logic = false
            for (CorExistente : CoresPresentes):
                if (CorExistente = Bola.Cor):
                    set JaTem = true

            if (not JaTem?):
                set CoresPresentes += array{Bola.Cor}

        var NovaCor : int = 0

        if (CoresPresentes.Length > 0):
            IndexSorteado := GetRandomIntSafe(0, CoresPresentes.Length - 1)

            if (CorSorteada := CoresPresentes[IndexSorteado]):
                set NovaCor = CorSorteada
        else:
            set NovaCor = GetRandomIntSafe(0, NumCoresAtivas - 1)

        set IndiceDaCorAtual = NovaCor

        if (Modelo := ModelosDeBolas[IndiceDaCorAtual]):
            T := SetaDeMira.GetTransform()
            Res := SpawnProp(Modelo, T.Translation, T.Rotation)
            if (B := Res(0)?):
                TransformMunicao := transform{Translation:=T.Translation, Rotation:=T.Rotation, Scale:=EscalaGlobal}
                if (B.TeleportTo[TransformMunicao]) {}
                set BolaNaBoca = option{B}

    AtirarBola()<suspends>:void=
        if (BolaVisual := BolaNaBoca?):
            if (P := GetPlayspace().GetPlayers()[0]):
                SomDisparo.Play(P)

            T_Saida := BolaVisual.GetTransform()
            CorTiro := IndiceDaCorAtual
            BolaVisual.Dispose()
            set BolaNaBoca = false

            var ModeloEncontrado : ?creative_prop_asset = false

            if (M := ModelosDeBolas[CorTiro]):
                set ModeloEncontrado = option{M}

            if (ModeloDefinitivo := ModeloEncontrado?):
                var RotTiro : rotation = T_Saida.Rotation
                if (P := GetPlayspace().GetPlayers()[0], F := P.GetFortCharacter[]):
                    set RotTiro = F.GetTransform().Rotation.ApplyLocalRotationZ(DegreesToRadians(GiroDaSeta))
                if (Bala := SpawnProp(ModeloDefinitivo, T_Saida.Translation, RotTiro)(0)?):
                    TransformBala := transform{Translation:=T_Saida.Translation, Rotation:=RotTiro, Scale:=EscalaGlobal}
                    if (Bala.TeleportTo[TransformBala]) {}
                    spawn{ MoverProjetil(Bala, CorTiro) }
                    Recarregar()

    MoverProjetil(Bala : creative_prop, CorDaBala : int)<suspends>:void=
        var TempoMax : float = 1.5 # Reduzido para 1.5s para evitar que atravesse fases
        Passo := 0.0
        loop:
            Sleep(Passo)
            T := Bala.GetTransform()
            DeltaTime := 0.016
            NovaPos := T.Translation + (T.Rotation.GetLocalForward() * (VelocidadeDoTiro * DeltaTime))
            TransformMovimento := transform{Translation:=NovaPos, Rotation:=T.Rotation, Scale:=EscalaGlobal}

            if (Bala.TeleportTo[TransformMovimento]):
                for (I := 0..Cobra.Length - 1):
                    if (BolaAlvo := Cobra[I]):
                        if (BolaAlvo.DistanciaNaTrilha > 0.0):
                            PosBala := NovaPos
                            PosAlvo := BolaAlvo.Prop.GetTransform().Translation
                            Distancia2D := Distance(vector3{X:=PosBala.X, Y:=PosBala.Y, Z:=0.0}, vector3{X:=PosAlvo.X, Y:=PosAlvo.Y, Z:=0.0})
                            if (Distancia2D < RaioDeColisao):
                                if (P := GetPlayspace().GetPlayers()[0]):
                                    SomImpacto.Play(P)
                                VetorFrente := BolaAlvo.Prop.GetTransform().Rotation.GetLocalForward()
                                VetorImpacto := PosBala - PosAlvo
                                Dot := DotProduct(VetorImpacto, VetorFrente)
                                var Lado : int = 0
                                if (Dot >= 0.0):
                                    set Lado = 0
                                else:
                                    set Lado = 1
                                InserirBolaNaCobra(I, Lado, Bala, CorDaBala)
                                return
            else:
                break
            set TempoMax -= DeltaTime
            if (TempoMax <= 0.0):
                Bala.Dispose()
                break

    InserirBolaNaCobra(IndiceAlvo : int, Lado : int, BolaProp : creative_prop, Cor : int):void=
        var IndexInsercao : int = IndiceAlvo
        var DistanciaBase : float = 0.0
        if (Alvo := Cobra[IndiceAlvo]):
            set DistanciaBase = Alvo.DistanciaNaTrilha
        if (Lado = 0):
            set IndexInsercao = IndiceAlvo
        else:
            set IndexInsercao = IndiceAlvo + 1
            set DistanciaBase = DistanciaBase - DiametroDaBola
        for (I := IndexInsercao..Cobra.Length - 1):
            if (Bola := Cobra[I]):
                set Bola.DistanciaNaTrilha -= DiametroDaBola
        set ContadorDeIds += 1

        NovaBola := dados_da_bola{
            Prop := BolaProp, Cor := Cor, Id := ContadorDeIds, DistanciaNaTrilha := DistanciaBase, Tipo := 0
        }
        TransformInsercao := transform{Translation:=BolaProp.GetTransform().Translation, Rotation:=BolaProp.GetTransform().Rotation, Scale:=EscalaGlobal}
        if (BolaProp.TeleportTo[TransformInsercao]) {}
        var NovaCobra : []dados_da_bola = array{}
        for (I := 0..IndexInsercao - 1):
            if (Item := Cobra[I]):
                set NovaCobra += array{Item}
        set NovaCobra += array{NovaBola}
        for (I := IndexInsercao..Cobra.Length - 1):
            if (Item := Cobra[I]):
                set NovaCobra += array{Item}
        set Cobra = NovaCobra
        spawn{ VerificarEExplodirSeguro(IndexInsercao, Cor, false) }

    VerificarEExplodirSeguro(Indice : int, Cor : int, EhAutomatico : logic)<suspends>:void=
        Sleep(0.0)
        VerificarEExplodir(Indice, Cor, EhAutomatico)

    VerificarEExplodir(IndiceAtingido : int, CorDoTiro : int, EhAutomatico : logic):void=
        if (ProcessandoExplosao?):
            return
        set ProcessandoExplosao = true

        # Reset ou Incremento do Combo
        if (not EhAutomatico?):
            set NivelDoCombo = 0

        if (IndiceAtingido < 0 or IndiceAtingido >= Cobra.Length):
            set ProcessandoExplosao = false
            return

        var Contagem : int = 1
        var IndicesParaDestruir : []int = array{}

        # --- VERIFICAÇÃO PARA TRÁS ---
        var OffsetTras : int = 1
        loop:
            IndiceVizinho := IndiceAtingido + OffsetTras
            if (Vizinho := Cobra[IndiceVizinho], BolaRef := Cobra[IndiceVizinho - 1]):

                # Check de distância (Gap Check)
                # FIX: Tolerância mais rígida (1.1 em vez de 1.5)
                DistanciaEntreElas := Abs(Vizinho.DistanciaNaTrilha - BolaRef.DistanciaNaTrilha)
                if (DistanciaEntreElas > DiametroDaBola * 1.1):
                    break

                if (Vizinho.Cor = CorDoTiro):
                    set Contagem += 1
                    set IndicesParaDestruir += array{IndiceVizinho}
                    set OffsetTras += 1
                else:
                    break
            else:
                break

        # --- VERIFICAÇÃO PARA FRENTE ---
        var OffsetFrente : int = 1
        loop:
            IndiceVizinho := IndiceAtingido - OffsetFrente
            if (IndiceVizinho < 0):
                break
            if (Vizinho := Cobra[IndiceVizinho], BolaRef := Cobra[IndiceVizinho + 1]):

                # Check de distância (1.1x)
                DistanciaEntreElas := Abs(Vizinho.DistanciaNaTrilha - BolaRef.DistanciaNaTrilha)
                if (DistanciaEntreElas > DiametroDaBola * 1.1):
                    break

                if (Vizinho.Cor = CorDoTiro):
                    set Contagem += 1
                    set IndicesParaDestruir += array{IndiceVizinho}
                    set OffsetFrente += 1
                else:
                    break
            else:
                break

        set IndicesParaDestruir += array{IndiceAtingido}

        if (Contagem >= 3):
            Print("COMBO! {Contagem} bolas.")

            if (EhAutomatico?):
                set NivelDoCombo += 1
                Print("CHAIN REACTION! Level {NivelDoCombo}")

            # XP via Lista de Accolades (Progressivo)
            if (P := GetPlayspace().GetPlayers()[0]):
                 var IndexXP : int = NivelDoCombo
                 if (ListaDeXP.Length > 0):
                     if (IndexXP >= ListaDeXP.Length):
                         set IndexXP = ListaDeXP.Length - 1
                     if (DispositivoCorreto := ListaDeXP[IndexXP]):
                         DispositivoCorreto.Award(P)

            var TemBomba : logic = false
            var TemSlow : logic = false
            var TemReverso : logic = false

            for (Idx : IndicesParaDestruir):
                if (Bola := Cobra[Idx]):
                    if (Bola.Tipo = 1):
                        set TemBomba = true
                    if (Bola.Tipo = 2):
                        set TemSlow = true
                    if (Bola.Tipo = 3):
                        set TemReverso = true

            if (TemBomba?):
                if (P := GetPlayspace().GetPlayers()[0]):
                    SomExplosaoBomba.Play(P)
                var CentroBomba : int = IndiceAtingido
                var MinIdx : int = CentroBomba - RaioDaExplosaoBomba
                var MaxIdx : int = CentroBomba + RaioDaExplosaoBomba
                for (I := MinIdx..MaxIdx):
                    if (I >= 0 and I < Cobra.Length):
                        var JaEsta : logic = false
                        for (K : IndicesParaDestruir):
                            if (K = I):
                                set JaEsta = true
                        if (not JaEsta?):
                            set IndicesParaDestruir += array{I}

            if (TemSlow?):
                if (P := GetPlayspace().GetPlayers()[0]):
                    SomAtivarSlow.Play(P)
                set TempoRestanteSlow = DuracaoDoSlowMotion

            if (TemReverso?):
                if (P := GetPlayspace().GetPlayers()[0]):
                    SomAtivarReverso.Play(P)
                set TempoRestanteReverso = DuracaoDoReverso

            if (not TemBomba?):
                if (P := GetPlayspace().GetPlayers()[0]):
                    # Lógica de som progressivo
                    var SomTocado : logic = false
                    if (EhAutomatico? and SonsCombo.Length > 0):
                        var IdxSom : int = NivelDoCombo - 1
                        if (IdxSom >= SonsCombo.Length):
                             set IdxSom = SonsCombo.Length - 1
                        if (SomExtra := SonsCombo[IdxSom]):
                            SomExtra.Play(P)
                            set SomTocado = true

                    if (not SomTocado?):
                        SomExplosao.Play(P)

            for (Indice : IndicesParaDestruir):
                if (BolaParaMorrer := Cobra[Indice]):
                    SpawnProp(ModeloExplosao, BolaParaMorrer.Prop.GetTransform().Translation, rotation{})
                    BolaParaMorrer.Prop.Dispose()

            RemoverEmMassa(IndicesParaDestruir)

        set ProcessandoExplosao = false

    RemoverEmMassa(IndicesParaRemover : []int):void=
        var NovaLista : []dados_da_bola = array{}
        for (I := 0..Cobra.Length - 1):
            var DeveManter : logic = true
            for (IndiceRuim : IndicesParaRemover):
                if (I = IndiceRuim):
                    set DeveManter = false
            if (DeveManter?, Item := Cobra[I]):
                set NovaLista += array{Item}
        set Cobra = NovaLista
        spawn{ ChecarVitoria() }