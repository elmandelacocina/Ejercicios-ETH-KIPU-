
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// @title Subasta Dinámica con Extensión y Reembolsos Parciales
// @notice Permite ofertar por un artículo, extendiendo el tiempo final con cada nueva oferta válida.
/*
* @notice Esta es la primer version que hice en español porque no sabia que se codeaba todo en ingles
* Gracias a esto igual pude revisar todo el codigo y despues de dos clases pude mejorar sustancialmente 
* el codigo del contrato, ademas de en la ultima clase aprender a importar librerias como la de OpenZeppelin
*/

contract Subasta {
    // @notice Dirección del dueño de la subasta
    address public immutable owner;

    // @notice Marca el inicio de la subasta (timestamp)
    uint256 public immutable inicioTiempo;

    // @notice Marca el final original de la subasta (timestamp)
    uint256 public immutable setTiempoFinal;

    // @notice Marca el final actualizado de la subasta (timestamp)
    uint256 public tiempoActualizado;

    // @notice Dirección del ofertante con la oferta más alta
    address public mayorOfertante;

    // @notice Valor de la oferta más alta
    uint256 public mayorOferta;

    // @notice Indica si la subasta ya fue finalizada
    bool public finalizada;

    // @notice Comisión de reembolso: 2% para ofertantes no ganadores
    uint256 public constant comision = 200; // 2% en basis points (1% = 100bps)

    // @notice Mapeo de las ofertas por dirección
    mapping(address => uint256) public ofertas;

    // @notice Lista de ofertantes únicos
    address[] public ofertantes;

    // @dev Registro auxiliar para evitar duplicados en ofertantes
    mapping(address => bool) private registrado;

    // @notice Evento emitido al realizar una nueva oferta válida
    event NuevaOferta(address indexed ofertante, uint256 amount, uint256 nuevoTiempoFinal);

    // @notice Evento emitido al finalizar la subasta
    event SubastaFinalizada(address ganador, uint256 amount);

    // @dev Modificador para restringir acceso al dueño
    modifier soloOwner() {
        require(msg.sender == owner, "Solo el dueno puede ejecutar");
        _;
    }

    // @dev Modificador para verificar si la subasta está activa
    modifier siEstaActiva() {
        require(block.timestamp >= inicioTiempo, "Subasta no ha iniciado");
        require(block.timestamp <= tiempoActualizado, "Subasta finalizada");
        _;
    }

    // @dev Modificador para una sola ejecución tras el fin de la subasta
    modifier soloSiTermino() {
        require(block.timestamp > tiempoActualizado, "Subasta aun activa");
        require(!finalizada, "Subasta ya finalizada");
        _;
    }

    /**
     * @notice Constructor de la subasta
     * @param _duracion Duración en segundos desde el inicio hasta el fin inicial
     */
    constructor(uint256 _duracion) {
        require(_duracion > 0, "Duracion invalida");
        owner = msg.sender;
        inicioTiempo = block.timestamp;
        setTiempoFinal = block.timestamp + _duracion;
        tiempoActualizado = setTiempoFinal;
    }

    /**
     * @notice Realiza una oferta. La oferta debe superar la actual en al menos 5%.
     * @dev Si se realiza dentro de los últimos 10 minutos, extiende la subasta por 10 minutos.
     */
    function ofertar() external payable siEstaActiva {
        require(msg.value > 0, "Debe enviar Ether");

        uint256 ofertaActual = ofertas[msg.sender] + msg.value;
        uint256 minimoRequerido = mayorOferta + (mayorOferta * 5) / 100;

        if (mayorOferta > 0) {
            require(ofertaActual >= minimoRequerido, "Oferta debe superar en al menos 5%");
        }

        if (!registrado[msg.sender]) {
            registrado[msg.sender] = true;
            ofertantes.push(msg.sender);
        }

        ofertas[msg.sender] = ofertaActual;
        mayorOferta = ofertaActual;
        mayorOfertante = msg.sender;

        if (block.timestamp >= tiempoActualizado - 10 minutes) {
            tiempoActualizado = block.timestamp + 10 minutes;
        }

        emit NuevaOferta(msg.sender, ofertaActual, tiempoActualizado);
    }

    /**
     * @notice Permite retirar parte del exceso de depósito durante la subasta.
     * @param amount Monto a retirar (debe ser menor o igual al total depositado)
     */
    function retirarExcedente(uint256 amount) external siEstaActiva {
        uint256 montoOferta = ofertas[msg.sender];
        require(montoOferta > 0, "No hay fondos depositados");
        require(msg.sender != mayorOfertante, "Ganador no puede retirar");
        require(amount > 0 && amount <= montoOferta, "Monto invalido");

        ofertas[msg.sender] = montoOferta - amount;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Fallo en el retiro");
    }

    /**
     * @notice Finaliza la subasta y habilita los retiros de depósitos para no ganadores.
     */
    function finalizarSubasta() external soloSiTermino {
        finalizada = true;
        emit SubastaFinalizada(mayorOfertante, mayorOferta);
    }

    /**
     * @notice Permite a ofertantes no ganadores retirar su depósito con un 2% de comisión.
     */
    function retirarDeposito() external {
        require(finalizada, "Subasta no ha finalizado");
        require(msg.sender != mayorOfertante, "Ganador no puede retirar aqui");

        uint256 amount = ofertas[msg.sender];
        require(amount > 0, "Nada que retirar");

        ofertas[msg.sender] = 0;

        uint256 fee = (amount * comision) / 10000;
        uint256 reembolso = amount - fee;

        (bool sent, ) = msg.sender.call{value: reembolso}("");
        require(sent, "Fallo en el reembolso");
    }

    /**
     * @notice Retorna la lista de todos los ofertantes y sus ofertas.
     * @return direcciones Array de direcciones de los ofertantes.
     * @return cantidad Array de montos ofertados por cada dirección.
     */
    function mostrarOfertas() external view returns (address[] memory direcciones, uint256[] memory cantidad) {
        uint256 len = ofertantes.length;
        direcciones = new address[](len);
        cantidad = new uint256[](len);

        for (uint256 i = 0; i < len; ++i) {
            address ofertante = ofertantes[i];
            direcciones[i] = ofertante;
            cantidad[i] = ofertas[ofertante];
        }
    }

    /**
     * @notice Retorna el ganador actual y la oferta ganadora.
     * @return ganador Dirección del ofertante con la oferta más alta.
     * @return oferta Monto de la oferta más alta.
     */
    function mostrarGanador() external view returns (address ganador, uint256 oferta) {
        return (mayorOfertante, mayorOferta);
    }

    /**
     * @notice Retorna el número de ofertantes únicos.
     * @return count Número de participantes únicos.
     */
    function numeroDeOfertantes() external view returns (uint256 count) {
        return ofertantes.length;
    }

    /**
     * @dev Rechaza depósitos directos a menos que sea mediante la función ofertar().
     */
    fallback() external payable {
        revert("Usa la funcion ofertar()");
    }

    receive() external payable {
        revert("Usa la funcion ofertar()");
    }
}
