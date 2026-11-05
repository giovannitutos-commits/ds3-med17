# Estado da migração Android Teste 12 → iOS

Esta é a primeira implementação nativa em Swift/SwiftUI. Uma compilação aprovada comprova que o código compila e passa pelos testes listados, **não comprova equivalência funcional total ao Android nem validação em veículo**.

## Implementado no código

- Catálogo: 80 perfis PSA, 2.819 descritores originais, 356 rotinas, tabelas DTC, identificação e ajuda técnica. Manifesto com SHA-256 do projeto de origem e dos recursos.
- ELM327 Wi-Fi TCP e Bluetooth LE UART, com UUIDs configuráveis. Transações em uma fila única, framing por prompt, limite de resposta e desligamento quando a sincronização é perdida.
- Protocolos CAN/KWP, endereços de categoria, keep-alive, identificação sem seleção aproximada, interpretação de telemetria 61FF restrita aos comandos permitidos, transforms numéricos e campos indisponíveis.
- OBD-II genérico: tabela de PIDs suportados, parâmetros, DTCs CAN/KWP, apagamento confirmado e freeze frame quadro zero. O monitor estabelece uma linha de base e não soa falhas arquivadas como se fossem novas.
- ECU motor e os oito PIDs TPMS fornecidos, intercalados, com restauração do endereço do motor. Fórmula original de pressão `(A*255+B)/69` preservada.
- Leitura opcional de centrais secundárias de câmbio, direção, aditivo e motor secundário, com restauração da sessão do motor.
- Painel configurável por orientação: seleção, ordem, colunas, cartões/barras/texto, largura, fonte, unidades, extremos, cores, escala e reset preservando alarmes. Ordem padrão transcrita do Android Teste 12.
- Três medidores com parâmetros, escalas e faixas de cor próprias, alinhados lado a lado em paisagem.
- Shiftlight com rotação real recente, alvo e antecipação, som, vibração e tela cheia.
- Alarmes por parâmetro, histerese, som/vibração, histórico e exportação CSV. Sons originais suave/duplo/triplo/SERVICE C4/DS3, importação de áudio personalizado e volume ajustável.
- Registros CSV, importação com preservação do original, estatísticas, comparação de sessões e gráficos ao vivo.
- Capturas de oficina, comparação antes/depois, exportação PDF e freeze frame sem confundir consulta com instante da falha.
- Viagens: integração de velocidade e combustível, cobertura explícita, fator de correção, mapa GPS e exportação GPX.
- Rotinas do catálogo com confirmação, verificação de motor/veículo parados, validação de respostas de início/parada, contador AL4/AM6, reset e releitura de aprendizado.
- Conexão automática opcional, temas, cor de destaque, conversão de temperatura/distância/pressão, registro de comunicação e saúde da conexão.
- Liquid Glass nativo no iOS 26; fallback do sistema no iOS 17–18. Ícone minimalista gerado como recurso nativo.
- Sem licença de teste, bloqueio por código ou prazo interno de validade.

## Diferenças e limitações conhecidas

- Android Auto não é portável para iPhone. CarPlay exige autorização/entitlement da Apple e não está incluído.
- Bluetooth clássico SPP de adaptadores comuns não está disponível por CoreBluetooth; use Wi-Fi ou BLE compatível. O transporte BLE genérico exige validação do protocolo UART do adaptador.
- O iOS controla a execução em segundo plano e não oferece o mesmo serviço permanente do Android. A versão de teste encerra a conexão quando esgota o tempo de execução permitido e interrompe rotinas ao ir para segundo plano.
- Ícones alternativos, painel de temas completo do Android, todos os filtros avançados dos registros e igualdade de textos/atalhos não estão integralmente reproduzidos nesta primeira versão.
- O funcionamento simultâneo dos módulos, recuperação de timeout TPMS, atuadores e reset em hardware depende de validação física. Não descreva esta versão como equivalente validada à versão Android.
- Instalação gratuita usa assinatura pessoal pelo Sideloadly; capacidades dependentes de entitlements pagos não são habilitadas.

## Verificação automatizada

O workflow executa XCTest com respostas MED17 gravadas, exceção 61FF, índices dos blocos de turbo, quadros truncados, signed transforms, PIDs OBD-II, fórmula TPMS, respostas DTC, total e integridade do catálogo, padrão de painel, parser/estatísticas CSV e bloco de data. XCUITest percorre as cinco abas e abre as configurações, anexando capturas de tela. Depois compila para iPhone ARM64 e verifica a estrutura do IPA.

Um resultado de teste deve ser consultado na execução do workflow; este documento não afirma que os testes já passaram.
