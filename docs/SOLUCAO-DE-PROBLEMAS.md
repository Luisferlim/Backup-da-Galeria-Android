# Solução de problemas

## O celular não é encontrado

1. Desbloqueie a tela.
2. Confirme que o cabo permite dados; alguns cabos servem apenas para carregar.
3. Selecione **Transferência de arquivos** nas opções USB do Android.
4. Verifique se a Depuração USB está ativada.
5. Clique novamente em **Verificar conexão**.

## O celular aparece como não autorizado

Aceite a mensagem **Permitir depuração USB?** exibida no aparelho. Se ela não aparecer:

1. desconecte o cabo;
2. use **Revogar autorizações de depuração USB** nas Opções do desenvolvedor;
3. reconecte e autorize novamente.

## Uma pasta do WhatsApp não existe

Isso é normal quando o WhatsApp não está instalado, não criou mídias ou utiliza outra estrutura na versão do Android. A pasta ausente é ignorada e o backup continua nas demais fontes.

## Um vídeo está demorando

A interface mostra o tamanho e o tempo decorrido. Vídeos grandes podem demorar vários minutos, dependendo do cabo, da porta USB e do armazenamento do celular.

Para interromper, clique em **Parar com segurança**. O processo ADB atual será encerrado, a cópia parcial no PC será descartada e o original permanecerá intacto. Ao executar novamente, o backup retomará os itens pendentes.

## A transferência desconectou

Reconecte e autorize o aparelho, abra a ferramenta e selecione a mesma pasta de destino. O manifesto fará com que arquivos concluídos sejam ignorados.

## Arquivos foram colocados no mês errado

Para JPEG/JPG, verifique a propriedade **Data da foto** no Windows. Quando a mídia não possui EXIF e o nome não contém uma data reconhecível, o programa utiliza a data de modificação disponível após a cópia.

## Há arquivos com `(2)` no nome

Isso indica que já havia outro arquivo com o mesmo nome, mas tamanho diferente, na pasta de destino. Ambos são mantidos para evitar perda de dados.

## Onde está o relatório?

Abra `ultimo-relatorio.json` na pasta escolhida para o backup. O arquivo registra quantos itens foram copiados, ignorados e quais apresentaram falha.

## O PowerShell foi bloqueado

O iniciador usa `ExecutionPolicy Bypass` apenas para os dois scripts localizados na própria pasta do programa. Em computadores administrados por uma organização, uma política corporativa pode impedir a execução; nesse caso, consulte o administrador.
