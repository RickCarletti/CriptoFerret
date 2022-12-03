// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title CriptoFerret
 * @dev The game consists of creating unique ferrets, as well as the possibility of creating a new ferret, or transferring it to another user.
 * @custom:dev-run-script ./scripts/deploy_with_ethers.ts
 */

contract Owner {
    address private owner;

    event OwnerSet(address indexed oldOwner, address indexed newOwner);

    modifier isOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    constructor() {
        console.log("Owner contract deployed by:", msg.sender);
        owner = msg.sender;
        emit OwnerSet(address(0), owner);
    }

    function changeOwner(address newOwner) public isOwner {
        emit OwnerSet(owner, newOwner);
        owner = newOwner;
    }

    function getOwner() external view returns (address) {
        return owner;
    }
}

contract Useful {
    uint32 GENE_SIZE = 10;
    uint256 randNonce = 0;

    function randMod(uint256 _modulus) internal returns (uint256) {
        // aumenta nonce
        randNonce++;
        return
            uint256(
                keccak256(
                    abi.encodePacked(block.timestamp, msg.sender, randNonce)
                )
            ) % _modulus;
    }

    function generateRandomGene() internal returns (string memory) {
        string memory randomGene = Strings.toString(
            randMod(10**(GENE_SIZE + 1))
        );
        while (bytes(randomGene).length < GENE_SIZE) {
            randomGene = string(abi.encodePacked("0", randomGene));
        }
        return randomGene;
    }
}

contract FerretBase is Owner, Useful {
    uint32 MAX_FERRET_GEN0 = 10;

    constructor(FerretBase) {
        //Criando o furão zero, ele não existe e não é de ninguém
        _createFerret(0, 0, 0, "", address(0));
    }

    //@EVENTOS
    event Transfer(address from, address to, uint16 ferretId);

    event Birth(
        address owner,
        uint256 ferretId,
        uint256 firstSireId,
        uint256 secondSireId,
        uint64 birthTime,
        string genes
    );

    struct Ferret {
        // O gene do furão não pode ser alterado
        string genes;
        // O tempo que o furão nasceu
        uint64 birthTime;
        // A data para poder fazer fusão novamente
        uint64 fusionTime;
        // Ids de ancestral
        uint32 firstSireId;
        uint32 secondSireId;
        // Numero da Geração do furão
        uint16 generation;
    }

    Ferret[] ferrets;

    // Qual endereço possui tal furão
    mapping(uint256 => address) public ferretIndexToOwner;

    // Quantos furões tal endereço tem
    mapping(address => uint256) ownershipTokenCount;

    function _createFerret(
        uint256 _firstSireId,
        uint256 _secondSireId,
        uint256 _generation,
        string memory _genes,
        address _owner
    ) internal returns (uint256) {
        uint64 birthTime = uint64(block.timestamp);
        Ferret memory _ferret = Ferret({
            genes: _genes,
            birthTime: birthTime,
            fusionTime: birthTime,
            firstSireId: uint32(_firstSireId),
            secondSireId: uint32(_secondSireId),
            generation: uint16(_generation)
        });

        ferrets.push(_ferret);
        uint256 newFerretId = ferrets.length - 1;

        ferretIndexToOwner[newFerretId] = _owner;
        ownershipTokenCount[_owner]++;

        // emit the birth event
        emit Birth(
            _owner,
            newFerretId,
            uint256(_ferret.firstSireId),
            uint256(_ferret.secondSireId),
            birthTime,
            _ferret.genes
        );

        return newFerretId;
    }

    // criando geração zero
    function createGen0(string memory _genes) public isOwner returns (bool) {
        if (ferrets.length < MAX_FERRET_GEN0) {
            if (bytes(_genes).length == 0) {
                _genes = generateRandomGene();
            } else {
                while (bytes(_genes).length < GENE_SIZE) {
                    _genes = string(abi.encodePacked("0", _genes));
                }
                //TODO : caso passar maior que o GENE_SIZE
            }
            _createFerret(0, 0, 0, _genes, msg.sender);
            return true;
        } else {
            return false;
        }
    }

    // criando função de transferencia privada
    function transfer(uint16 ferretId, address _to) public returns (bool) {
        //verifico se o furão que quero trasnferir é meu
        if (ferretIndexToOwner[ferretId] != msg.sender) {
            return false; //se não for não trasfere
        }

        //trasfiro o furão para o novo dono
        ferretIndexToOwner[ferretId] = _to;

        //removo um furão do meu contador
        ownershipTokenCount[msg.sender]--;

        //adiciono um novo furão ao contador do novo dono
        ownershipTokenCount[_to]++;

        //emito evento de transferencia
        emit Transfer(msg.sender, _to, ferretId);

        return true;
    }

    function ferretFusion(uint16 ferretId1, uint16 ferretId2)
        public
        returns (uint256)
    {
        //só é possível fazer a fusão se ambos os furões sejão meus
        if (
            ferretIndexToOwner[ferretId1] == msg.sender &&
            ferretIndexToOwner[ferretId2] == msg.sender
        ) {
            // só será possivel fazer a fusão se ambos os furões puderem se fundir
            if (canFusion(ferretId1) && canFusion(ferretId2)) {
                //defino qual vai ser a geração é a maior geração entre os dois mais 1
                uint256 generation = ferrets[ferretId1].generation + 1;

                if (
                    ferrets[ferretId1].generation <
                    ferrets[ferretId2].generation
                ) {
                    generation = ferrets[ferretId2].generation + 1;
                }

                string memory newGene = geneFusion(
                    ferrets[ferretId1].genes,
                    ferrets[ferretId2].genes
                );

                uint256 newFerretId = _createFerret(
                    ferretId1,
                    ferretId2,
                    generation,
                    newGene,
                    msg.sender
                );

                // uma semana = 604800
                // um dia = 86400

                ferrets[ferretId1].fusionTime = uint64(block.timestamp) + 86400; // define que só poderá ser feita fusão novamente em n timestamp
                ferrets[ferretId2].fusionTime = uint64(block.timestamp) + 86400; // define que só poderá ser feita fusão novamente em n timestamp

                return newFerretId;
            }
        }
        return 0;
    }

    function geneFusion(string memory gene1, string memory gene2)
        internal
        returns (string memory)
    {
        bytes memory outputGene = new bytes(10);
        for (uint256 i = 0; i < 10; i++) {
            uint256 teste = randMod(2);
            if (teste == 0) {
                outputGene[i] = bytes(gene1)[i];
            } else {
                outputGene[i] = bytes(gene2)[i];
            }
        }
        return string(outputGene);
    }

    function canFusion(uint16 ferretId) public returns (bool) {
        return ferrets[ferretId].fusionTime < uint64(block.timestamp);
    }

    function getFerret(uint16 ferretId)
        public
        returns (
            address owner,
            string memory genes,
            uint64 birthTime,
            uint64 fusionTime,
            uint32 firstSireId,
            uint32 secondSireId,
            uint16 generation,
            bool isReady
        )
    {
        Ferret storage fer = ferrets[ferretId];

        owner = ferretIndexToOwner[ferretId];
        genes = fer.genes;
        fusionTime = uint64(fer.fusionTime);
        firstSireId = uint32(fer.firstSireId);
        birthTime = uint64(fer.birthTime);
        secondSireId = uint32(fer.secondSireId);
        generation = uint16(fer.generation);
        isReady = canFusion(ferretId);
    }

    function getFerretQuantity(address _location)
        public
        returns (uint256 count)
    {
        count = ownershipTokenCount[_location];
    }
}
