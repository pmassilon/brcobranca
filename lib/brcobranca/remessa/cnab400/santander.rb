# -*- encoding: utf-8 -*-
#
module Brcobranca
  module Remessa
    module Cnab400
      class Santander < Brcobranca::Remessa::Cnab400::Base
        # Código de Transmissão
        # Consultar seu gerente para pegar esse código. Geralmente está no e-mail enviado pelo banco.
        attr_accessor :codigo_transmissao
        attr_accessor :convenio
        attr_accessor :digito_agencia

        attr_accessor :codigo_carteira

        attr_accessor :aceite
        # 'A' – para sim, ou 'N' – para não

        attr_accessor :identificador_complemento
        # INFORMAR NESTE CAMPO CARACTERE 'I' (i maiúsculo)

        attr_accessor :primeira_instrucao
        attr_accessor :segunda_instrucao
        attr_accessor :instrucao_cobranca

        validates_presence_of :documento_cedente, :agencia, :conta_corrente, :digito_conta, message: 'não pode estar em branco.'
        validates_length_of :documento_cedente, minimum: 11, maximum: 14, message: 'deve ter entre 11 e 14 dígitos.'
        validates_length_of :carteira, maximum: 3, message: 'deve ter no máximo 3 dígitos.'

        def initialize(campos = {})
          campos = { aceite: 'A', carteira: '101', digito_agencia: ' ', codigo_carteira: '5', identificador_complemento: 'I', primeira_instrucao: '00', segunda_instrucao: '00', instrucao_cobranca: '05' }.merge!(campos)
          super(campos)
        end

        def cod_banco
          '033'
        end

        def nome_banco
          'SANTANDER'.format_size(15)
        end

        # Informacoes do Código de Transmissão
        #
        # @return [String]
        #
        def info_conta
          # CAMPO                     TAMANHO
          # codigo_transmissao        20
          unless codigo_transmissao
            codigo_transmissao = ''
            codigo_transmissao << agencia.rjust(4, '0').format_size(4, '0')
            codigo_transmissao << convenio.rjust(8, '0').format_size(8, '0')
            codigo_transmissao << conta_corrente[0..-2].rjust(8, '0').format_size(8, '0')
          end

          codigo_transmissao.format_size(20, '0')
        end

        def info_agencia_cobradora
          agencia_cobradora = ''
          agencia_cobradora << agencia.rjust(4, '0').format_size(4, '0')
          agencia_cobradora << digito_agencia.rjust(1, '0').format_size(1, '0')
        end

        # Complemento do header
        #
        # @return [String]
        #
        def complemento
          ''.rjust(275, ' ')
        end

        # Complemento zeros do header
        #
        # @return [Integer]
        #
        def complemento_zeros
          '0'.rjust(16, '0')
        end

        # Header do arquivo remessa
        #
        # @return [String]
        #
        def monta_header
          header = ''                                                       # CAMPO                 TAMANHO    VALOR
          header << '0'                                                     # tipo do registro      [1]        0
          header << '1'                                                     # operacao              [1]        1
          header << 'REMESSA'                                               # literal remessa       [7]        REMESSA
          header << '01'                                                    # Código do serviço     [2]        01
          header << 'COBRANCA'.ljust(15, ' ')                               # cod. servico          [15]       COBRANCA
          header << info_conta                                              # info. conta           [20]
          header << empresa_mae.format_size(30)                             # empresa mae           [30]
          header << cod_banco                                               # cod. banco            [3]
          header << nome_banco                                              # nome banco            [15]
          header << data_geracao                                            # data geracao          [6]        formato DDMMAA
          header << complemento_zeros                                       # Zeros.................[16]
          header << complemento                                             # complemento registro  [274]      Brancos
          header << '000'                                                   # Versao da remessa.....[3]        Numero da versao da remessa opcional, se informada, sera controlada pelo sistema (opcional = 000)
          header << '000001'                                                # num. sequencial       [6]        000001
          header
        end

        # Detalhe do arquivo
        #
        # @param pagamento [PagamentoCnab400]
        #   objeto contendo as informacoes referentes ao boleto (valor, vencimento, cliente)
        # @param sequencial
        #   num. sequencial do registro no arquivo
        #
        # @return [String]
        #
        def monta_detalhe(pagamento, sequencial)
          raise Brcobranca::RemessaInvalida, pagamento if pagamento.invalid?

          detalhe = '1'                                                     # identificacao transacao               9[01]
          detalhe << Brcobranca::Util::Empresa.new(documento_cedente).tipo  # tipo de identificacao da empresa      9[02]
          detalhe << documento_cedente.to_s.rjust(14, '0')                  # cpf/cnpj da empresa                   9[14]
          detalhe << info_conta                                             # Código de Transmissão                 9[20]
          detalhe << ''.rjust(25, ' ')                                      # identificacao do tit. na empresa      X[25]
          detalhe << formatar_nosso_numero(pagamento.nosso_numero)          # nosso numero                          9[07]
          detalhe << digito_nosso_numero(formatar_nosso_numero(pagamento.nosso_numero))       # nosso numero                          9[01]
          detalhe << ''.rjust(6, '0')                                       # data limite para o segundo desconto   9[06]
          detalhe << ' '                                                    # brancos                               X[01]
          detalhe << pagamento.codigo_multa                                 # Com multa = 4, Sem multa = 0          9[01]
          detalhe << pagamento.formata_valor_multa(4)                       # Percentual multa por atraso %         9[04]
          detalhe << '00'                                                   # Unidade de valor moeda corrente = 00  9[02]
          detalhe << '0'.rjust(13, '0')                                     # Valor do título em outra unidade      9[13]
          detalhe << ''.rjust(4, ' ')                                       # brancos                               X[04]
          detalhe << pagamento.formata_data_multa                           # Data para cobrança de multa           9[06]

          # codigo da carteira
          # 1 = ELETRÔNICA COM REGISTRO
          # 3 = CAUCIONADA ELETRÔNICA
          # 4 = COBRANÇA SEM REGISTRO
          # 5 = RÁPIDA COM REGISTRO
          # (BLOQUETE EMITIDO PELO CLIENTE) 6 = CAUCIONADA RAPIDA
          # 7 = DESCONTADA ELETRÔNICA
          detalhe << codigo_carteira # codigo da carteira                    9[01]

          # Código da ocorrência:
          # 01 = ENTRADA DE TÍTULO
          # 02 = BAIXA DE TÍTULO
          # 04 = CONCESSÃO DE ABATIMENTO
          # 05 = CANCELAMENTO ABATIMENTO
          # 06 = PRORROGAÇÃO DE VENCIMENTO
          # 07 = ALT. NÚMERO CONT.CEDENTE
          # 08 = ALTERAÇÃO DO SEU NÚMERO
          # 09 = PROTESTAR
          # 18 = SUSTAR PROTESTO
          detalhe << pagamento.identificacao_ocorrencia                     # identificacao ocorrencia              9[02]
          detalhe << pagamento.numero_documento.to_s.rjust(10, ' ')         # numero do documento                   X[10]
          detalhe << pagamento.data_vencimento.strftime('%d%m%y')           # data do vencimento                    9[06]
          detalhe << pagamento.formata_valor                                # valor do documento                    9[13]
          detalhe << cod_banco                                              # codigo banco                          9[03]
          # Código da agência cobradora do Banco Santander,
          # opcional informar somente se carteira for igual a 5,
          # caso contrário, informar zeros.
          detalhe << info_agencia_cobradora                                 # agencia cobradora.....................9[05]

          # Espécie de documento:
          # 01 = DUPLICATA
          # 02 = NOTA PROMISSÓRIA
          # 03 = APÓLICE / NOTA DE SEGURO
          # 05 = RECIBO
          # 06 = DUPLICATA DE SERVIÇO
          # 07 = LETRA DE CAMBIO
          detalhe << pagamento.especie_titulo                               # Espécie de documento                  9[02]
          detalhe << aceite                                                 # aceite (A/N)                          X[01]
          detalhe << pagamento.data_emissao.strftime('%d%m%y')              # data de emissao                       9[06]

          # Instrução cobrança
          # 00 = NÃO HÁ INSTRUÇÕES
          # 02 = BAIXAR APÓS QUINZE DIAS DO VENCIMENTO
          # 03 = BAIXAR APÓS 30 DIAS DO VENCIMENTO
          # 04 = NÃO BAIXAR
          # 06 = PROTESTAR (VIDE POSIÇÃO392/393)
          # 07 = NÃO PROTESTAR
          # 08 = NÃO COBRAR JUROS DE MORA
          detalhe << primeira_instrucao.rjust(2, '0')                       # Instrução para o título               9[02]
          detalhe << segunda_instrucao.rjust(2, '0')                        # Número de dias válidos para instrução 9[02]
          detalhe << pagamento.formata_valor_mora                           # valor mora ao dia                     9[13]
          detalhe << pagamento.formata_data_desconto                        # data limite para desconto             9[06]
          detalhe << pagamento.formata_valor_desconto                       # valor do desconto                     9[13]
          detalhe << pagamento.formata_valor_iof                            # valor do iof                          9[13]
          detalhe << pagamento.formata_valor_abatimento                     # valor do abatimento                   9[13]
          detalhe << pagamento.identificacao_sacado.rjust(2, '0')           # identificacao do pagador              9[02]
          detalhe << pagamento.documento_sacado.to_s.rjust(14, '0')         # documento do pagador                  9[14]
          detalhe << pagamento.nome_sacado.format_size(40).ljust(40, ' ')   # nome do pagador                       X[40]
          detalhe << pagamento.endereco_sacado.format_size(40).ljust(40, ' ') # endereco do pagador                   X[40]
          detalhe << pagamento.bairro_sacado.format_size(12).ljust(12, ' ') # bairro do pagador                     X[12]
          detalhe << pagamento.cep_sacado                                   # cep do pagador                        9[08]
          detalhe << pagamento.cidade_sacado.format_size(15)                # cidade do pagador                     X[15]
          detalhe << pagamento.uf_sacado                                    # uf do pagador                         X[02]
          # SE O CEDENTE FOR PESSOA JURÍDICA, O MESMO NÃO PODE TER SACADOR AVALISTA. DEIXAR CAMPO EM BRANCO
          detalhe << ''.rjust(30, ' ')                                      # Sacador                              X[30]
          detalhe << ''.rjust(1, ' ')                                       # Brancos                               X[1]
          # INFORMAR NESTE CAMPO CARACTERE 'I' (i maiúsculo)
          detalhe << identificador_complemento                              # Identificador do Complemento          X[1]
          detalhe << complemento_remessa                                    # Complemento                           9[2]
          detalhe << ''.rjust(6, ' ')                                       # Brancos                               X[06]
          # Se identificacao_ocorrencia = 06
          detalhe << instrucao_cobranca.ljust(2, '0')                       # Número de dias para protesto          9[02]
          detalhe << ''.rjust(1, ' ')                                       # Brancos                               X[1]
          detalhe << sequencial.to_s.rjust(6, '0')                          # numero do registro no arquivo         9[06]
          detalhe
        end

        # Trailer do arquivo remessa
        #
        # @param sequencial
        #   num. sequencial do registro no arquivo
        #
        # @return [String]
        #
        def monta_trailer(sequencial)
          # CAMPO                                 TAMANHO  VALOR
          # identificacao registro                [1]      9
          # Quantidade total de linhas no arquivo [6]
          # Valor total dos títulos               [13]
          # zeros                                 [374]
          # num. sequencial                       [6]
          "9#{sequencial.to_s.rjust(6, '0')}#{valor_total_titulos(13)}#{''.rjust(374, '0')}#{sequencial.to_s.rjust(6, '0')}"
        end

        private

        # Complemento de remessa
        #
        # @return [String]
        #
        def complemento_remessa
          # [99]
          # ultimo digito da conta corrente
          # digito da conta corrente
          "#{conta_corrente[-1]}#{digito_conta}"
        end

        def digito_nosso_numero(nosso_numero)
          nosso_numero.to_s.modulo11(
            multiplicador: [2,3,4,5,6,7,8,9],
            mapeamento: { 10 => '1', 11 => '0', 1 => '0' }
          ) { |total| 11 - (total % 11) }.to_s
        end

        def formatar_nosso_numero(nosso_numero)
          nosso_numero.to_s.rjust(7, '0').format_size(7)
        end
      end
    end
  end
end
