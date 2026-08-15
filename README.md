# Backup da Galeria Android

Ferramenta local para Windows que copia fotos e vídeos de um celular Android pelo cabo USB, organiza os arquivos em pastas de ano e mês e retoma transferências interrompidas.

```text
Backup do celular/
├── 2024/
│   ├── 01/
│   └── 12/
├── 2025/
└── 2026/
    └── 08/
```

O programa não envia arquivos para a internet e não executa comandos de exclusão no celular.

## Recursos

- Interface gráfica em português para Windows.
- Cópia via Android Debug Bridge (ADB) pelo cabo USB.
- Organização automática em `AAAA\MM`.
- Leitura da data original EXIF de fotos JPEG.
- Alternativas pela data no nome ou pela data do arquivo.
- Retomada após desconexão ou interrupção.
- Detecção de arquivos já concluídos por caminho e tamanho.
- Tratamento de arquivos diferentes com o mesmo nome.
- Parada segura inclusive durante a cópia de vídeos grandes.
- Relatório JSON com arquivos copiados, ignorados e falhas.

## Requisitos

- Windows 10 ou Windows 11.
- Celular Android.
- Cabo USB que suporte transferência de dados.
- PowerShell 5.1 ou superior, incluído no Windows.
- Depuração USB ativada temporariamente no aparelho.

O pacote já contém os componentes necessários do Android Platform Tools 37.0.1.

## Como usar

1. Baixe ou clone este repositório.
2. No Android, abra **Configurações → Sobre o telefone** e toque sete vezes em **Número da versão** para habilitar as Opções do desenvolvedor. O nome pode variar conforme o fabricante.
3. Em **Opções do desenvolvedor**, ative **Depuração USB**.
4. Conecte e desbloqueie o celular.
5. Execute `Abrir Backup da Galeria.cmd`.
6. Clique em **Verificar conexão** e aceite a autorização exibida no celular.
7. Escolha uma pasta no computador e clique em **Iniciar backup**.

Mantenha o aparelho desbloqueado e, em backups longos, conectado ao carregador. Confira algumas fotos e vídeos no computador antes de apagar qualquer conteúdo do celular.

## Pastas consultadas

O programa procura mídias nestes locais:

- `/sdcard/DCIM`
- `/sdcard/Pictures`
- `/sdcard/Movies`
- imagens do WhatsApp em `Android/media`
- vídeos do WhatsApp em `Android/media`

Pastas opcionais ausentes são ignoradas. Miniaturas em `.thumbnails` não são copiadas.

## Formatos aceitos

Fotos: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.heic`, `.heif` e `.dng`.

Vídeos: `.mp4`, `.mov`, `.m4v`, `.3gp`, `.mkv`, `.avi` e `.webm`.

## Retomada e arquivos auxiliares

Na pasta escolhida pelo usuário, o programa cria:

- `.backup-celular.json`: manifesto usado para reconhecer arquivos concluídos.
- `.transferindo`: armazenamento temporário de uma cópia em andamento.
- `ultimo-relatorio.json`: resultado da execução mais recente.

Se o backup for interrompido, execute novamente usando a mesma pasta. Itens concluídos serão ignorados. Uma cópia parcial é removida sem afetar o original no celular.

## Segurança e privacidade

- O funcionamento é local entre o computador e o aparelho conectado.
- A ferramenta usa apenas busca, consulta de propriedades e `adb pull` no Android.
- Não há comando para apagar ou modificar mídias no aparelho.
- O número de série e o modelo servem somente para identificar o dispositivo durante a execução.

Depois de concluir e conferir o backup, desative a Depuração USB e, se desejar, revogue as autorizações de depuração nas Opções do desenvolvedor. Consulte também [SECURITY.md](SECURITY.md).

## Documentação adicional

- [Arquitetura e funcionamento](docs/ARQUITETURA.md)
- [Solução de problemas](docs/SOLUCAO-DE-PROBLEMAS.md)

## Componentes de terceiros

Este repositório inclui arquivos do Android SDK Platform Tools distribuídos pelo Google. Os avisos correspondentes estão em [`platform-tools/NOTICE.txt`](platform-tools/NOTICE.txt).

Este projeto ainda não declara uma licença própria. Os direitos dos componentes de terceiros permanecem regidos por seus respectivos avisos.
