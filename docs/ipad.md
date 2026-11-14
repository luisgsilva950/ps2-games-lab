# PS2 Games Lab no iPad — build nativo experimental

Este alvo compila um **app nativo independente baseado no Play!**, com emulação
no próprio iPad. Não transmite jogos de um computador e não precisa de servidor
Rails durante a partida. É um companion de execução: **não é um port da interface
Rails**, do chat, dos ajustes PCSX2 ou do banco de dados do laboratório. A biblioteca,
os controles de toque, o suporte a controles físicos e os saves são os do Play!;
não existe sincronização com a biblioteca do Mac.

**Estado: experimental e sem validação em dispositivo físico.** Gerar um IPA não
comprova que ele instala, que o JIT funciona na sua versão do iPadOS, ou que um jogo
roda com desempenho aceitável. A versão fixada neste repositório não inclui uma
correção própria para JIT nas versões recentes do iPadOS.

## Limitação importante: instalação e JIT

O PCSX2 atual do laboratório suporta plataformas desktop; gerar um executável ARM
não o transforma em um app para iPadOS. Por isso este alvo usa o Play!, que possui
frontend iOS e BIOS de alto nível própria. Nenhum BIOS ou jogo é incluído no build.

O artefato `PS2GamesLab-unsigned.ipa` recebe apenas assinatura **ad-hoc para
empacotamento**. Não contém certificado Apple nem perfil de provisionamento e não
instala ao tocar no arquivo no Safari/Arquivos. Precisa ser re-assinado e provisionado
por um método de desenvolvimento/sideload compatível com seu dispositivo. Não
envie certificados, senhas ou credenciais Apple para o repositório.

O Play! nativo também exige **JIT habilitado**. O upstream informa que iniciar um
jogo sem JIT provoca crash. Assinar ou instalar o IPA, por si só, não habilita JIT.
O método de ativação depende da versão do iPadOS e pode exigir computador ou
serviço auxiliar. Não há promessa de configuração totalmente sem computador.
Uma sessão que usa o debugger pode continuar após desacoplar o Mac, mas encerrar
o processo pode exigir nova ativação. Confirme o método aplicável antes de instalar.

Referências oficiais:

- [PCSX2: plataformas suportadas](https://pcsx2.net/docs/setup/running/)
- [Play!: requisitos iOS, JIT e transferência de jogos](https://github.com/jpd002/Play-#running-on-ios)
- [AltStore: ativação de JIT e duração da sessão](https://faq.altstore.io/altstore-classic/enabling-jit)
- [Compatibilidade de jogos no Play!](https://github.com/jpd002/Play-Compatibility)

## Gerar e baixar o executável

1. No GitHub, abra **Actions → Build iPadOS**. A PR executa o build automaticamente;
   após merge também é possível usar **Run workflow**.
2. Espere o job `native` concluir com sucesso. Baixe o artefato
   **PS2GamesLab-iPadOS-unsigned**. Em caso de falha não há IPA publicado.
3. Extraia o arquivo: ele inclui o IPA, `SHA256SUMS`, este guia e os avisos/licenças
   com o commit e as revisões dos submódulos usados no build.
4. Re-assine/provisione e instale pelo método compatível com seu iPadOS. Ative JIT
   conforme a documentação do upstream. Isso ainda requer validação no seu aparelho.

Para compilar localmente, use macOS com Xcode completo selecionado, SDK iPhoneOS,
CMake, Python 3 e Git:

```sh
script/build-ipados
```

O script busca um **commit completo fixo** em `ios/play-revision.txt`, inicializa
os submódulos nas revisões gravadas e usa uma pasta de build nova. Não usa `latest`
nem instala dependências de sistema. A saída fica em `tmp/ipados/dist/`. O renderer
é OpenGL ES; Vulkan/MoltenVK não é incluído neste alvo inicial. O build verifica o
bundle para iPad, o executável arm64, storyboard, assinatura ad-hoc e checksum.
Essas verificações são de build e empacotamento, não de gameplay.

## Jogos, controles e saves no iPad

Depois da instalação e configuração de JIT:

1. No app **Arquivos**, copie sua imagem de jogo para a pasta do app em
   **No Meu iPad**. O bundle habilita compartilhamento de arquivos e documentos
   locais. Mantenha backup antes de reinstalar ou apagar o app.
2. Reabra o app para que o Play! examine sua pasta e monte a biblioteca. Escolha
   um jogo. Use apenas imagens que você tem direito de usar.
3. Experimente os controles virtuais do Play! ou pareie um controle compatível
   com o iPad. Valide botões e analógicos no jogo; o perfil PCSX2 do Mac não é usado.
4. Saves e configurações ficam no sandbox do app. Não são os saves do PCSX2 e
   podem ser removidos ao desinstalar. Não há migração automática entre emuladores.

O Play! pode buscar títulos e capas na rede conforme seu comportamento upstream;
este build não adiciona API de IA, upload de ISO ou servidor do laboratório.

## Validação pendente antes de chamar de pronto

- Instalar no modelo e versão de iPadOS pretendidos; registrar o método de assinatura/JIT.
- Importar uma imagem autorizada, abrir biblioteca e iniciar jogo compatível.
- Verificar imagem, áudio, controles virtuais/físicos e desempenho por uma partida real.
- Salvar, fechar, reabrir e recuperar progresso; testar interrupção e reativação de JIT.

O nome do companion é **PS2 Lab (Play!)**, com identificador
`com.luisgsilva950.ps2gameslab`. O emulador continua sendo o Play!, de Jean-Philip
Desjardins e colaboradores. As mudanças locais são identidade do bundle e inclusão
de documentação/licenças; a lógica de emulação e de JIT permanece upstream.
